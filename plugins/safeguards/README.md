# safeguards

A **hooks-only** Claude Code plugin that bundles defensive `PreToolUse` guards.
Each guard inspects a tool call *before* it runs and **denies** (exit 2) the
dangerous ones. The guards are active automatically whenever the plugin is
enabled — **no setup, no credentials, no MCP servers**.

| Guard | Tools it watches | What it blocks |
| --- | --- | --- |
| **Credential-read guard** | `Read`, `Bash` | Reading files that commonly hold secrets |
| **AI-attribution guard** | `Bash` | `git commit`s with a `Co-Authored-By: Claude` / "Generated with Claude" trailer |
| **Force-push guard** | `Bash` | `git push --force` to a protected branch (`main`/`master`) |

A deny is **per call** — it blocks only that one tool invocation, never your
session. See [Bypass / disable](#bypass--disable).

> Heads-up: the `Bash` coverage in every guard is **best-effort**. A shell can
> express the same dangerous action in countless ways a text-matching hook can't
> fully catch (variable expansion, `eval`, aliases, indirection, …). Treat the
> Bash branches as defence-in-depth, not a guarantee. The `Read` branch of the
> credential guard is the only airtight control here.

## Install

```
/plugin marketplace add carlosrberto/cc-plugins
/plugin install safeguards@cc-plugins
/reload-plugins
```

## Guards

### 1. Credential-read guard (`hooks/credential-guard.sh`)

Blocks Claude from **reading files that commonly hold secrets**, so their
contents never land in the conversation.

- It guards the **Read** tool by inspecting `tool_input.file_path` (the real
  control).
- It **best-effort** guards the **Bash** tool by scanning `tool_input.command`
  for a direct file reader (`cat`, `head`, `tail`, `less`, `more`, `bat`,
  `strings`, `xxd`, `od`, `nl`, `view`, `vi`, `vim`, `nano`, `emacs`) aimed at a
  denylisted path. A shell can read a file in ways no hook can fully catch, so
  don't rely on the Bash branch as a guarantee.

**Denylist** (matched on basename and path segments):

- **`.env` family** — `.env` and any `.env.*`, **except** the non-secret
  templates `.env.example`, `.env.sample`, `.env.template`, `.env.dist`, which
  are **allowed**.
- **Shell startup files** — `.zshrc`, `.zshenv`, `.zprofile`, `.zlogin`,
  `.bashrc`, `.bash_profile`, `.bash_login`, `.profile`.
- **Credential files** — `credentials.json`, `.netrc`, `.pgpass`, `.npmrc`,
  `.pypirc`, `.git-credentials`, `.aws/credentials`, `.docker/config.json`,
  `.kube/config`.
- **Private keys** — `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`, and any
  `*.pem` / `*.key`.

Edit the denylist block at the top of `hooks/credential-guard.sh` to adjust it.
If `jq` is missing the guard fails **closed** for the Read tool (denies) and
open for unrelated tools.

### 2. AI-attribution guard (`hooks/ai-attribution-guard.sh`)

Blocks a `git commit` (including `--amend`) whose **inline** message text
contains an AI-attribution trailer. Matching is case-insensitive and catches:

- `Co-Authored-By: Claude`
- a generic `Co-authored-by:` line that names `Claude` or
  `noreply@anthropic.com`
- `Generated with Claude`
- `🤖 Generated with`

Everything else is allowed.

**Limitation:** the guard can only see message text that appears **inline in the
Bash command** — `git commit -m "…"`, `-F <heredoc>`, or a heredoc body. It
**cannot** see a message you type into the editor that `git commit` opens (with
no `-m`/`-F`), because that text never appears in the command string. So this is
a best-effort guard for the common inline-commit case, not a guarantee.

### 3. Force-push guard (`hooks/force-push-guard.sh`)

Blocks `git push` carrying a force flag (`--force`, `--force-with-lease`, or a
`-f` standalone/short-cluster token) when it targets a **protected branch**.

- **Protected branches:** `main`, `master` (an editable list at the top of the
  script; release patterns like `release/*` could be added there).
- **Force-pushing a feature branch is allowed** — the guard only fires for
  protected targets.

**Target detection (best-effort):**

1. If the command explicitly names a protected branch as a refspec
   (`git push --force origin main`, `… HEAD:main`), it is denied.
2. If the command names no explicit *other* branch, the guard reads the hook
   payload's `.cwd` and runs `git -C "$cwd" rev-parse --abbrev-ref HEAD`; if the
   **current branch** is protected, the push is denied.

A push that targets a protected branch through an indirect refspec, a configured
`push.default`, a remote-tracking alias, or variable expansion can slip through —
hence best-effort.

## Bypass / disable

A deny is **per call** — it blocks one Read/Bash/commit/push, not your session.
To proceed when a guard is in your way, pick the lightest option that fits:

- **Do it yourself.** Open the secret file, run the commit, or run the force-push
  from your own terminal — the guard only intercepts Claude's tool calls.
- **Edit the lists.** Each guard keeps its denylist / protected-branch list as an
  editable block at the **top of its script** (`hooks/*.sh`). Adjust and
  `/reload-plugins`.
- **Disable the plugin.** `/plugin` → disable `safeguards` →
  `/reload-plugins`. Re-enable it the same way afterwards.

## Roadmap / future guards

Candidates not yet implemented:

- **Secret-commit guard** — block `git add` / `git commit` of denylisted secret
  files (the credential denylist applied to staging, not just reading).
- **Secret-write guard** — block `Write`/`Edit` of secret-looking content (API
  keys, private-key blocks, tokens) into tracked files.
- **Catastrophic-command guard** — block `rm -rf` of broad paths (`/`, `~`,
  `$HOME`), `chmod -R 777`, and `dd`/disk-wipe commands.
- **Protected-path write guard** — block writes to `~/.ssh`, shell rc files,
  `.git/hooks`, and `.github/workflows`.

## Tradeoff

These are **plugin-level** hooks, so while `safeguards` is enabled they apply
to **all** `Read` and `Bash` tool calls in the session — a deliberate
defence-in-depth choice. If a guard's matching is too broad for your workflow,
edit its list or disable the plugin rather than working around it silently.
