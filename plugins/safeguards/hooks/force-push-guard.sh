#!/usr/bin/env bash
# PreToolUse hook: block force-pushes (`git push --force`/`--force-with-lease`/
# `-f`) that target a PROTECTED branch. Force-pushing a feature branch is fine
# and is allowed.
#
# Fires on the Bash tool only. Exit 0 = allow, exit 2 = deny (stderr shown to
# the model). Portable: bash + jq only (+ optional `git` for branch detection).
#
# IMPORTANT — BEST-EFFORT: target-branch detection cannot be airtight. We deny
# when (a) the command explicitly names a protected branch as a refspec, or
# (b) the command names no explicit branch and the current branch (read from the
# hook payload's .cwd via `git rev-parse`) is protected. A push that targets a
# protected branch through an indirect refspec, a configured push.default, a
# remote-tracking alias, or variable expansion can slip through. Treat as
# defence-in-depth, not a guarantee.
set -euo pipefail

# ---------------------------------------------------------------------------
# PROTECTED BRANCHES — edit here. Force-pushes to these are denied.
# (Release patterns like release/* could be added with extra matching below.)
# ---------------------------------------------------------------------------
PROTECTED_BRANCHES=(main master)
# ---------------------------------------------------------------------------

payload="$(cat)"

# Fail closed only for the relevant case: without jq we cannot parse the
# command, so block any Bash command mentioning `git push` and allow the rest.
if ! command -v jq >/dev/null 2>&1; then
  case "$payload" in
    *'git push'*) echo "Blocked by force-push-guard: 'jq' is required to evaluate the push guard but was not found on PATH." >&2; exit 2 ;;
    *) exit 0 ;;
  esac
fi

tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Must be a `git push`.
case "$cmd" in
  *"git "*"push"*) ;;
  *) exit 0 ;;
esac

is_protected() {
  local b="$1"
  [ -n "$b" ] || return 1
  local p
  for p in "${PROTECTED_BRANCHES[@]}"; do
    [ "$b" = "$p" ] && return 0
  done
  return 1
}

# --- detect a force flag -------------------------------------------------
# Tokenize the command and look for --force / --force-with-lease / a `-f` that
# appears standalone or inside a short-flag cluster (e.g. -uf).
normalized="${cmd//[;|&()]/ }"
normalized="${normalized//$'\n'/ }"
# shellcheck disable=SC2086  # deliberate word-splitting to tokenize
set -- $normalized

has_force=0
explicit_protected=""   # set if a protected branch is named on the command line
explicit_other=0        # set if some non-protected ref is explicitly named
seen_push=0
for tok in "$@"; do
  case "$tok" in
    --force | --force-with-lease | --force-with-lease=*)
      has_force=1 ;;
    --*) ;;  # other long flag — ignore
    -*)
      # Short-flag (cluster): a literal `f` among the letters means --force.
      case "$tok" in
        *f*) has_force=1 ;;
      esac
      ;;
    push) seen_push=1 ;;
    *)
      # Positional args after `push` are <remote> and <refspec(s)>. The first
      # positional is the remote; subsequent ones are refspecs. We don't know
      # the remote name, so just test EVERY positional token against the
      # protected list (a refspec like `main` or `HEAD:main` or `local:main`).
      if [ "$seen_push" -eq 1 ] && [ "$tok" != "git" ]; then
        # Extract the destination side of a `src:dst` refspec, else the token.
        ref="${tok##*:}"
        ref="${ref##*/}"   # strip any refs/heads/ prefix
        if is_protected "$ref"; then
          explicit_protected="$ref"
        else
          # A bare remote name (e.g. `origin`) also lands here; that's fine —
          # it just means "not an explicit protected ref". Track only things
          # that look like a branch ref (contain `:` or aren't the first arg).
          case "$tok" in
            *:*) explicit_other=1 ;;
          esac
        fi
      fi
      ;;
  esac
done

[ "$has_force" -eq 1 ] || exit 0   # not a force-push → allow

deny() {
  echo "Blocked by force-push-guard: refusing to force-push to protected branch '$1'. Force-pushing main/master can destroy shared history. Force-push a feature branch instead, or see the bypass note in the safeguards README." >&2
  exit 2
}

# (a) An explicitly-named protected branch → deny.
if [ -n "$explicit_protected" ]; then
  deny "$explicit_protected"
fi

# (b) No explicit OTHER branch named → fall back to the current branch via the
# payload's .cwd. If the current branch is protected, deny.
if [ "$explicit_other" -eq 0 ]; then
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
  if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    cur="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if is_protected "$cur"; then
      deny "$cur (current branch)"
    fi
  fi
fi

exit 0
