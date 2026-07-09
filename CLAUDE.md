# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal **Claude Code plugin marketplace**. `.claude-plugin/marketplace.json`
is the catalog; each plugin lives under `plugins/<name>/`. Current plugins:

- **`safeguards`** — a **hooks-only** plugin (no skills/commands/agents) bundling three defensive `PreToolUse` guards: a credential-read guard, an AI-attribution commit guard, and a protected-branch force-push guard. No credentials or MCP servers. Active for all matching tool calls whenever it's enabled.
- **`announce`** — a **hooks-only** plugin (no skills/commands/agents) that speaks Claude's status aloud via macOS `say`, preceded by an `afplay` earcon chime, on the `Stop`, `Notification`, `UserPromptSubmit`, and `SubagentStop` events. No credentials or MCP servers. Informational and fail-open: never blocks a turn, exits 0, writes nothing to stdout, and no-ops on non-macOS hosts.

The marketplace name is `cc-plugins`. Plugin names are intentionally different
from the marketplace name (a plugin named identically to its marketplace can
confuse `/plugin install <plugin>@<marketplace>` invocations at a glance).

**Where docs go** (keep each doc to its audience): `README.md` = install and
usage. `CONTRIBUTING.md` = plugin development (repo layout, local dev,
`plugin_validate`, commit/release). Per-plugin usage lives in
`plugins/<name>/README.md`. This file (`CLAUDE.md`) = conventions for working
in the repo.

## Architecture

`plugins/safeguards/` is **hooks-only** — no skills, commands, agents, helpers,
or credentials. It registers three **plugin-level `PreToolUse` guards** in
`plugins/safeguards/hooks/hooks.json` (deny-by-`exit 2`; portable bash + jq,
fail-closed for the relevant case). Because they're plugin-level they apply to
*all* matching tool calls whenever the plugin is enabled — a deliberate
defence-in-depth tradeoff. Each guard keeps its editable list (denylist /
protected branches) as a block at the top of its script:

- `hooks/credential-guard.sh` — blocks reads of secret-bearing files. Guards
  `Read` (`tool_input.file_path`, the real control) and **best-effort** `Bash`
  (direct `cat`/`head`/… readers). Denylist: `.env`/`.env.*` (except
  non-secret templates), shell rc/profile files, `credentials.json`,
  `.netrc`/`.pgpass`/`.npmrc`/`.git-credentials`, SSH private keys,
  `*.pem`/`*.key`, `.aws/credentials`, `.docker/config.json`, `.kube/config`.
- `hooks/ai-attribution-guard.sh` — blocks a `git commit` (incl. `--amend`)
  whose **inline** message text carries an AI-attribution trailer
  (`Co-Authored-By: Claude`, a `Co-authored-by:` line naming
  Claude/`noreply@anthropic.com`, `Generated with Claude`,
  `🤖 Generated with`). **Limitation:** sees only inline `-m`/`-F`/heredoc
  text, not editor-typed messages.
- `hooks/force-push-guard.sh` — blocks `git push --force`/`--force-with-lease`/`-f`
  to a protected branch (`main`/`master`). **Best-effort** target detection:
  denies an explicitly-named protected refspec, else reads the payload's
  `.cwd` and denies when the current branch
  (`git rev-parse --abbrev-ref HEAD`) is protected. Feature-branch
  force-pushes are allowed.

`plugins/announce/` is **hooks-only** — no skills, commands, agents, or
credentials. `hooks/hooks.json` wires four events to one script,
`hooks/announce.sh`, passing an event tag as `$1`; each announcement plays an
`afplay` earcon chime and then the phrase:

- `Stop` → `announce.sh finish` — speaks `PHRASE_FINISH` ("Claude is done.").
- `Notification` → `announce.sh input` — speaks the payload's `.message`
  (permission / idle prompt), falling back to `PHRASE_INPUT`.
- `UserPromptSubmit` → `announce.sh start` — speaks `PHRASE_START`.
- `SubagentStop` → `announce.sh subagent` — speaks `PHRASE_SUBAGENT`.

Deliberately does **not** hook `PreToolUse`/`PostToolUse` (per-command /
per-file chatter drowns the signal) — only the four "come back" moments. The
script is **informational, non-blocking, fail-open**: it exits 0 always, writes
**nothing to stdout** (critical for `UserPromptSubmit`, whose stdout feeds prompt
context), plays audio in a detached background subshell (`( … & )`) so Claude is
never delayed, and no-ops when `say` isn't on PATH (non-macOS). Editable config
(per-event toggles, phrases, `SOUND_*` earcons, `VOICE`, `RATE`) lives in a block
at the top of the script. Written for macOS's stock bash 3.2 — explicit `say`
branches, no arrays.

## Conventions for working in this repo

- **Plugin naming.** A plugin's manifest name should read naturally in
  `/plugin install <name>@cc-plugins`.
- **Hooks are best-effort for Bash, airtight for structured tools.** Every
  guard's docstring states its limitation plainly — don't silently widen a
  guard's claimed coverage beyond what it can actually enforce.
- **Editable lists live at the top of each script**, not buried in logic, so
  they're easy to tune without reading the whole guard.
- **`scripts/plugin_validate` must pass** before a commit that touches a
  plugin manifest or hook script. It runs `shellcheck`, JSON validation, and
  `claude plugin validate`.
- **Version bumps ship changes.** Marketplace/plugin update detection is
  version-string equality — a plugin change without a version bump in
  `plugin.json` is invisible to installed users. Use
  `scripts/plugin_bump <plugin> <major|minor|patch>`.
