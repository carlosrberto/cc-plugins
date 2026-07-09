# Contributing

Working on the `cc-plugins` Claude Code marketplace.

## Repo layout

A marketplace (`.claude-plugin/marketplace.json`) of plugins under `plugins/`:

- **`safeguards`** — hooks-only: credential-read, AI-attribution, and force-push guards.

Supporting the marketplace:

- **`scripts/`** — repo dev tooling: `plugin_validate`, `plugin_bump`.
- **`.githooks/pre-push`** — runs `scripts/plugin_validate` (enable with `core.hooksPath`).

Each plugin's internals live in its own `README.md`; see [`CLAUDE.md`](./CLAUDE.md) for the architecture overview. (Keep this list current only when a **plugin** is added or removed — not for every new skill or helper.)

## Prerequisites

Runtime tools (`bash`, `jq`) plus **`shellcheck`** (lint scripts) and the
**`claude` CLI** (validate + load the plugin). On macOS:

```bash
brew install jq shellcheck
```

## Local development

Load the plugin directly from the working copy (fastest iteration):

```
claude --plugin-dir ./plugins/safeguards
```

After editing, run `/reload-plugins` to pick up changes — hook/manifest edits
need the reload.

### Verify before committing/pushing

```
./scripts/plugin_validate
```

This runs `shellcheck` (scripts + hooks), `jq` validity of the manifests, and
`claude plugin validate` for the plugin and the marketplace. The tracked
**pre-push hook** runs it automatically — activate it once per clone:

```
git config core.hooksPath .githooks
```

(The hook is bypassable with `git push --no-verify` and is local-only; there is
no CI gate yet.)

## Commits & branches

Conventional Commits for both. Branches: `<type>/<short-description>` (kebab-case).
Commits: `<type>(<scope>): <subject>` where scope is the component — a plugin
name (`safeguards`) or an area (`marketplace`, `docs`). Types:
`feat fix chore refactor docs test perf`.

## Releasing

Bump the plugin's version (required to ship changes to installed users — update
detection is version-string equality, so commits alone don't reach them):

```
./scripts/plugin_bump <plugin> <major|minor|patch>   # e.g. ./scripts/plugin_bump safeguards minor
```

Then commit, e.g. `chore(safeguards): release v1.1.0`.
