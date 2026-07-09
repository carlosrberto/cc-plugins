#!/usr/bin/env bash
# PreToolUse hook: block reads of files that commonly hold secrets.
#
# Plugin-level guard (registered in hooks/hooks.json). It fires for two tools:
#   - Read: inspects tool_input.file_path and denies a denylisted target.
#   - Bash: best-effort — inspects tool_input.command for a file-reading
#           command (cat/head/tail/less/…) aimed at a denylisted path.
#
# Exit 0 = allow, exit 2 = deny (stderr is shown to the model).
# Portable: bash + jq only. Never echoes file contents.
#
# IMPORTANT: the Bash branch is BEST-EFFORT and cannot be airtight. A shell
# command can read a file in countless ways this hook will never catch
# (variable expansion, eval, base64, python -c, redirection into a reader,
# `source`, globbing, etc.). It catches the obvious, direct cases only; treat
# it as defence-in-depth, not a guarantee. The Read branch is the real control.
set -euo pipefail

# ---------------------------------------------------------------------------
# DENYLIST — edit here. Three independently-matched groups.
# ---------------------------------------------------------------------------

# 1. Exact basenames that are always secret-bearing.
DENY_BASENAMES=(
  credentials.json
  .zshrc .zshenv .zprofile .zlogin
  .bashrc .bash_profile .bash_login .profile
  .netrc .pgpass .npmrc .pypirc .git-credentials
  id_rsa id_dsa id_ecdsa id_ed25519
)

# 2. Basename glob patterns (case-sensitive shell globs).
DENY_BASENAME_GLOBS=(
  '*.pem' '*.key'
)

# 3. Path-segment suffixes — match when the file path ENDS with one of these
#    (handles dotfile dirs like ~/.aws/credentials regardless of the prefix).
DENY_PATH_SUFFIXES=(
  .aws/credentials
  .docker/config.json
  .kube/config
)

# .env handling is special-cased below: deny `.env` and `.env.*`, but ALLOW
# these non-secret templates.
ENV_TEMPLATE_SUFFIXES=(example sample template dist)

# ---------------------------------------------------------------------------

# Read all of stdin once so we can re-query it (a hook only gets one stdin).
payload="$(cat)"

# If jq is missing we cannot inspect anything. The Read tool is the control we
# care about, so fail closed only for it; for other tools, allow (we can't tell
# what the tool even is without jq, but blocking unrelated tools on a jq hiccup
# is worse than the best-effort gap). Detect the tool name with a plain check.
if ! command -v jq >/dev/null 2>&1; then
  case "$payload" in
    *'"Read"'*) echo "Blocked by credential-guard: 'jq' is required to evaluate the read guard but was not found on PATH." >&2; exit 2 ;;
    *) exit 0 ;;
  esac
fi

tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"

# Return 0 (deny) if the given path matches the denylist, 1 otherwise.
is_denied() {
  local path="$1"
  [ -n "$path" ] || return 1

  # Basename = text after the last slash.
  local base="${path##*/}"

  # --- .env family ---
  case "$base" in
    .env)
      return 0 ;;
    .env.*)
      # Allow known non-secret templates (.env.example, .env.sample, …).
      local suffix="${base#.env.}"
      local tmpl
      for tmpl in "${ENV_TEMPLATE_SUFFIXES[@]}"; do
        [ "$suffix" = "$tmpl" ] && return 1
      done
      return 0 ;;
  esac

  # --- exact basenames ---
  local b
  for b in "${DENY_BASENAMES[@]}"; do
    [ "$base" = "$b" ] && return 0
  done

  # --- basename globs ---
  local g
  for g in "${DENY_BASENAME_GLOBS[@]}"; do
    # shellcheck disable=SC2053  # intentional glob match, not literal compare
    [[ "$base" == $g ]] && return 0
  done

  # --- path-segment suffixes ---
  local s
  for s in "${DENY_PATH_SUFFIXES[@]}"; do
    case "$path" in
      *"/$s" | "$s") return 0 ;;
    esac
  done

  return 1
}

deny_read() {
  echo "Blocked by credential-guard: '$1' is on the secret-file denylist (.env, shell rc/profile, credential & key files). Reading it could leak secrets into the conversation. If you genuinely need it, see the bypass note in the safeguards README." >&2
  exit 2
}

deny_bash() {
  echo "Blocked by credential-guard: the Bash command appears to read '$1', which is on the secret-file denylist. Reading it could leak secrets into the conversation. If you genuinely need it, see the bypass note in the safeguards README." >&2
  exit 2
}

case "$tool" in
  Read)
    path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
    if is_denied "$path"; then
      deny_read "$path"
    fi
    exit 0
    ;;

  Bash)
    # Best-effort. Tokenize the command on shell metacharacters and whitespace,
    # then for any token that follows a known file-reading command, test it.
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    [ -n "$cmd" ] || exit 0

    # File-reading commands we attempt to catch. Includes search/stream tools
    # (grep/rg/sed/awk/jq/…) whose file argument follows a pattern/program token
    # — the arg loop below tests every non-flag token, so the path is still seen.
    readers=" cat head tail less more bat strings xxd od nl view vi vim nano emacs grep egrep fgrep rg ripgrep sed awk gawk jq yq gron cut paste sort uniq column "

    # Split into whitespace-separated words, but first turn shell separators
    # (; | & ( ) and newlines) into spaces so the start of each sub-command is
    # detected and a reader's arguments after a pipe/chain are still examined.
    # We replace separators with a sentinel token so we can reset reader state.
    normalized="${cmd//[;|&()]/ § }"
    normalized="${normalized//$'\n'/ § }"

    # shellcheck disable=SC2086  # deliberate word-splitting to tokenize
    set -- $normalized
    in_reader=0   # 1 once we've seen a reader command in the current sub-command
    for tok in "$@"; do
      # A sentinel marks a new sub-command: reset reader context.
      if [ "$tok" = "§" ]; then
        in_reader=0
        continue
      fi
      # Strip surrounding quotes a model might include around a path.
      clean="${tok%\"}"; clean="${clean#\"}"
      clean="${clean%\'}"; clean="${clean#\'}"

      if [ "$in_reader" -eq 1 ]; then
        # Inside a reader command: every non-flag token is a candidate path.
        case "$clean" in
          -*) ;;  # option flag (e.g. tail -n) — skip, stay in reader context
          *) if is_denied "$clean"; then deny_bash "$clean"; fi ;;
        esac
      fi

      # Does this token start a reader command? (env-var prefixes / paths like
      # /bin/cat also count.)
      case " $readers " in
        *" ${clean##*/} "*) in_reader=1 ;;
      esac
    done
    exit 0
    ;;

  *)
    # Irrelevant tool — nothing to guard.
    exit 0
    ;;
esac
