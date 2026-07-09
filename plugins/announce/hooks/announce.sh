#!/usr/bin/env bash
# Speak Claude Code's status aloud via macOS `say` (with an optional earcon
# chime via `afplay`), so you can step away and be called back when Claude
# finishes, starts, needs your input, or a subagent wraps up.
#
# Invoked by four hooks, each passing the event name as $1:
#   Stop              -> "finish"    : Claude finished responding
#   Notification      -> "input"     : Claude needs permission / is waiting on you
#   UserPromptSubmit  -> "start"     : you just handed Claude a new task
#   SubagentStop      -> "subagent"  : a subagent finished its task
#
# INFORMATIONAL, NON-BLOCKING, FAIL-OPEN. This hook never blocks a turn or a
# tool call: it always exits 0, writes NOTHING to stdout (so it can't pollute
# UserPromptSubmit's prompt context), and plays sound in the background so
# Claude is never delayed. On any non-macOS host (no `say` on PATH) it silently
# does nothing.
set -uo pipefail

# ===========================================================================
# CONFIG — edit here, then /reload-plugins.
# ===========================================================================
# Per-event toggles (1 = announce, 0 = stay silent).
SPEAK_ON_FINISH=1     # Stop: Claude finished responding
SPEAK_ON_INPUT=1      # Notification: Claude needs permission / is waiting
SPEAK_ON_START=1      # UserPromptSubmit: you gave Claude a new task
SPEAK_ON_SUBAGENT=1   # SubagentStop: a subagent finished

# What to say. The Notification event prefers the system's own message text
# (e.g. "Claude needs your permission to use Bash"); PHRASE_INPUT is its fallback.
PHRASE_FINISH="Claude is done."
PHRASE_INPUT="Claude needs your input."
PHRASE_START="Claude is on it."
PHRASE_SUBAGENT="A subagent finished."

# Earcon — a short chime played (via afplay) just BEFORE the phrase, so each
# event has its own recognizable sound. Set any to "" to skip the chime for
# that event. macOS ships these in /System/Library/Sounds (*.aiff).
SOUND_FINISH="/System/Library/Sounds/Glass.aiff"
SOUND_INPUT="/System/Library/Sounds/Ping.aiff"
SOUND_START="/System/Library/Sounds/Tink.aiff"
SOUND_SUBAGENT="/System/Library/Sounds/Bottle.aiff"

# Voice & speed. Run `say -v '?'` to list installed voices; set VOICE="" for
# the system default. RATE is words-per-minute (empty = default, ~175).
VOICE="Samantha"
RATE=""
# ===========================================================================

# Not macOS / no `say` → nothing to do.
command -v say >/dev/null 2>&1 || exit 0

event="${1:-}"
payload="$(cat 2>/dev/null || true)"

# Pull a string field from the JSON payload; empty if jq is missing or absent.
field() {
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null || true
}

phrase=""
sound=""
case "$event" in
  finish)
    [ "$SPEAK_ON_FINISH" = 1 ] || exit 0
    phrase="$PHRASE_FINISH"; sound="$SOUND_FINISH"
    ;;
  input)
    [ "$SPEAK_ON_INPUT" = 1 ] || exit 0
    phrase="$(field '.message')"
    [ -n "$phrase" ] || phrase="$PHRASE_INPUT"
    sound="$SOUND_INPUT"
    ;;
  start)
    [ "$SPEAK_ON_START" = 1 ] || exit 0
    phrase="$PHRASE_START"; sound="$SOUND_START"
    ;;
  subagent)
    [ "$SPEAK_ON_SUBAGENT" = 1 ] || exit 0
    phrase="$PHRASE_SUBAGENT"; sound="$SOUND_SUBAGENT"
    ;;
  *)
    exit 0
    ;;
esac

[ -n "$phrase" ] || exit 0

# Play the earcon (if present) then speak. Explicit `say` branches keep this
# working on macOS's stock bash 3.2 (no arrays) and quiet under set -u.
announce() {
  if [ -n "$sound" ] && [ -f "$sound" ] && command -v afplay >/dev/null 2>&1; then
    afplay "$sound"
  fi
  if [ -n "$VOICE" ] && [ -n "$RATE" ]; then
    say -v "$VOICE" -r "$RATE" "$phrase"
  elif [ -n "$VOICE" ]; then
    say -v "$VOICE" "$phrase"
  elif [ -n "$RATE" ]; then
    say -r "$RATE" "$phrase"
  else
    say "$phrase"
  fi
}

# Run detached in the background: the subshell starts the job and exits
# immediately, so the hook returns instantly and the audio outlives it.
( announce >/dev/null 2>&1 & )

exit 0
