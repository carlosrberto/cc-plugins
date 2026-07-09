#!/usr/bin/env bash
# PreToolUse hook: block `git commit` commands that carry an AI-attribution
# trailer in their INLINE message text. Enforces this repo's "No AI attribution"
# rule (no `Co-Authored-By: Claude` / "Generated with Claude" footers).
#
# Fires on the Bash tool only. Exit 0 = allow, exit 2 = deny (stderr shown to
# the model). Portable: bash + jq only.
#
# IMPORTANT — LIMITATION: this hook can only inspect message text that appears
# INLINE in the command string, i.e. `git commit -m "…"`, `-F <heredoc>`, or a
# heredoc body. It CANNOT see a message typed into the editor that `git commit`
# opens (no -m/-F), because that text never appears in the Bash command. So this
# is a best-effort guard for the common inline-message case, not a guarantee.
set -euo pipefail

# Read all of stdin once (a hook gets one stdin).
payload="$(cat)"

# Fail closed only for the relevant case: if jq is missing we cannot tell
# whether this is a git commit, so block any Bash command that mentions
# `git commit` (string match on the raw payload) and allow everything else.
if ! command -v jq >/dev/null 2>&1; then
  case "$payload" in
    *'git commit'*) echo "Blocked by ai-attribution-guard: 'jq' is required to evaluate the commit guard but was not found on PATH." >&2; exit 2 ;;
    *) exit 0 ;;
  esac
fi

tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Only care about `git commit` invocations (covers `git commit`, `git commit
# --amend`, `git -C path commit`, etc.). Match the `commit` subcommand after a
# `git` token, tolerating intervening global flags.
case "$cmd" in
  *"git "*"commit"*) ;;
  *) exit 0 ;;
esac

# Case-insensitive scan of the whole command string for AI-attribution markers.
# (Restricting to the exact -m/-F text would miss heredocs and odd quoting; the
# command is already known to be a git commit, so a broad scan is acceptable and
# strictly safer.)
lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

deny() {
  echo "Blocked by ai-attribution-guard: this commit message contains an AI-attribution trailer ($1), which this repo forbids. Remove the 'Co-Authored-By: Claude' / 'Generated with Claude' line and commit again. (See the safeguards README.)" >&2
  exit 2
}

case "$lc" in
  *"co-authored-by: claude"*)            deny "Co-Authored-By: Claude" ;;
  *"generated with claude"*)             deny "Generated with Claude" ;;
  *"🤖 generated with"*)                  deny "🤖 Generated with" ;;
esac

# Generic `Co-authored-by:` line attributing Claude / Anthropic (any spacing of
# the name on the same line as the trailer).
case "$lc" in
  *"co-authored-by:"*)
    case "$lc" in
      *"co-authored-by:"*"claude"* | *"co-authored-by:"*"noreply@anthropic.com"*) deny "Co-authored-by: …Claude/anthropic" ;;
    esac
    ;;
esac

exit 0
