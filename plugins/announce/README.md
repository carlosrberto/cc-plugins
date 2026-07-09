# announce

A **hooks-only** Claude Code plugin that **speaks Claude's status aloud** using
the built-in macOS `say` command, each announcement preceded by a distinct
**earcon** chime (via `afplay`) so you can identify the event by sound alone —
so you can step away from the terminal and be called back when something
happens. Active automatically whenever the plugin is enabled — **no setup, no
credentials, no MCP servers**.

| Event | Hook | Chime | What you hear |
| --- | --- | --- | --- |
| **Claude finishes a turn** | `Stop` | Glass | *"Claude is done."* |
| **Claude needs your input** | `Notification` | Ping | the actual prompt, e.g. *"Claude needs your permission to use Bash"* (falls back to *"Claude needs your input."*) |
| **You start a new task** | `UserPromptSubmit` | Tink | *"Claude is on it."* |
| **A subagent finishes** | `SubagentStop` | Bottle | *"A subagent finished."* |

> **macOS only.** It uses the system `say` command. On any other OS (no `say`
> on PATH) the hook does nothing — it never errors and never blocks.

The hook is **informational and non-blocking**: it always exits 0, speaks in the
background so Claude is never delayed, and writes nothing to the conversation.

## Install

```
/plugin marketplace add carlosrberto/cc-plugins
/plugin install announce@cc-plugins
/reload-plugins
```

## Configure

All settings live in an editable block at the top of
[`hooks/announce.sh`](./hooks/announce.sh). Edit it, then `/reload-plugins`.

- **Per-event toggles** — set `SPEAK_ON_FINISH`, `SPEAK_ON_INPUT`,
  `SPEAK_ON_START`, or `SPEAK_ON_SUBAGENT` to `0` to silence that event. For
  example, if the start-of-task announcement is noise when you're sitting right
  there, set `SPEAK_ON_START=0`.
- **Phrases** — `PHRASE_FINISH`, `PHRASE_INPUT`, `PHRASE_START`,
  `PHRASE_SUBAGENT`. The `Notification` event prefers the system's own message
  text and uses `PHRASE_INPUT` only as a fallback.
- **Earcons** — `SOUND_FINISH`, `SOUND_INPUT`, `SOUND_START`, `SOUND_SUBAGENT`
  are paths to a chime played just before the phrase. Defaults are macOS system
  sounds (`/System/Library/Sounds/*.aiff`; run `ls` there to see the set). Set
  any to `""` to drop the chime for that event and keep only speech.
- **Voice** — `VOICE` (defaults to `Samantha`; empty = system default). List
  installed voices with `say -v '?'`.
- **Speed** — `RATE` in words-per-minute (empty = default, ~175).

## How it works

`hooks/hooks.json` wires four Claude Code events to the one script, passing an
event tag as an argument:

- `Stop` → `announce.sh finish`
- `Notification` → `announce.sh input`
- `UserPromptSubmit` → `announce.sh start`
- `SubagentStop` → `announce.sh subagent`

The script reads the hook JSON payload on stdin (used only to pull the
`Notification` message), picks a chime + phrase, and plays them in a detached
background subshell (earcon via `afplay`, then speech via `say`) so the hook
returns immediately and Claude is never delayed.

### The `Notification` event

Claude Code fires `Notification` when it **needs your permission to run a tool**
and when the **input has been idle** for a while. In both cases the payload
carries a human-readable `message`, which is exactly what gets spoken — so you
hear *why* Claude wants you, not just that it does.

## Disable

- **Silence one event** — set its `SPEAK_ON_*` toggle to `0` and
  `/reload-plugins`.
- **Disable the plugin** — `/plugin` → disable `announce` → `/reload-plugins`.

## Why not announce every tool call?

A tempting extension is to hook `PreToolUse: Bash` ("Starting task") or
`PostToolUse: Edit/Write` ("File updated") — but those fire on *every* command
and *every* file write, producing near-constant chatter that drowns out the
signal. This plugin deliberately announces only the **four "come back" moments**:
a turn ends, a new task begins, input is needed, or a subagent wraps up. If you
do want per-tool cues, add them in your own `settings.json` rather than here, so
this plugin stays focused. (The `announce.sh` script already accepts an event
tag as `$1`, so a new event is a one-line hook + a new `case` branch.)

## Notes & limitations

- **macOS only** by design (`say` + `afplay`). A cross-platform version would
  need a per-OS speech/sound backend (e.g. `spd-say`/`espeak` + `paplay` on
  Linux, PowerShell speech on Windows); not implemented.
- Announcements are **local audio only** — nothing leaves your machine, nothing
  is written to the conversation.
- `Stop` fires at the end of Claude's turn; a follow-up tool round or a
  continued turn will announce again when it next stops. That's intended — each
  "come back" moment gets its own cue.
