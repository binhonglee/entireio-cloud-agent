---
name: entireio-cloud-agent
description: Wire up Entire (entire.io) AI-agent session capture in a cloud/headless coding-agent environment (Claude Code on the web, Cursor Cloud Agent, an SSH'd-in dev VM, etc.) so every agent session is captured and linked to Git history as a checkpoint. Use when the user wants agent sessions recorded/checkpointed in a repo that a remote agent works in, asks to "set up Entire", "enable Entire capture", install the `entire` CLI + hooks in a container, or make checkpoints survive across fresh cloud-agent VMs. NOT for building an Entire viewer/feature into an app's own UI — this is agent-session capture wiring only.
---

# Entire Cloud-Agent Capture Setup

Wire a repo so that when Claude Code runs in a **fresh cloud/headless VM**
(Claude Code on the web, an SSH'd-in dev VM, …), its session is captured by
[Entire](https://entire.io) and linked to Git history as a **checkpoint**, with
no manual steps per session.

This skill is about **capturing agent work into Git**, not about consuming or
displaying Entire data inside an application. If the user wants to render
checkpoints in their own app UI, that is a product-feature task — out of scope
here.

## What Entire is (the parts that matter for setup)

Entire captures every AI-agent coding session and links it to Git as a searchable
**checkpoint**. A checkpoint is created when the agent commits during a session,
so checkpoints are naturally keyed to commits. Mechanically there are three moving
parts you must get onto a fresh VM:

1. **The `entire` CLI** (and the `git-remote-entire` helper for platform sync).
2. **Agent lifecycle hooks** — per-agent hooks that call `entire hooks <agent> <event>`
   (session-start, user-prompt-submit, pre/post-task, stop, session-end). These
   live in the agent's own committed config (e.g. `.claude/settings.json`), so
   they are already armed when the agent starts.
3. **Git hooks** — a `commit-msg`/`post-commit` set that stamps the
   `Entire-Checkpoint` trailer and manages the `entire/checkpoints/v1` ref. These
   live in `.git/hooks`, which is **not version-controlled**, so they must be
   **re-armed every session** with `entire configure`.

Capture modes:

- **Local git capture** — no login. Checkpoints are written as git objects on the
  `entire/checkpoints/v1` ref in the local repo.
- **Platform sync (entire.io)** — set `ENTIRE_TOKEN` (a bearer from
  `entire auth token` on a logged-in machine) as an environment secret. Capture
  then rides a normal `git commit` + `git push`; the git hooks push the
  checkpoints ref alongside your branch.

## When to use / not use

Use when a **remote agent** works in a repo and the human wants the sessions
captured/checkpointed automatically. The defining problem this solves: cloud-agent
VMs are **ephemeral and fresh each session** — the CLI isn't installed, PATH isn't
set, and `.git/hooks` are empty. Something has to re-establish all of that at
session start, every time.

Do **not** use this skill for:

- Building an Entire **viewer / feature** into an application's own UI (graph
  overlays, detail panes, resume buttons) — that's product work, not capture setup.
- Browser or desktop **screenshot/recording** capture — see a `headless-capture`
  style skill instead.

## What you're building

For the primary (Claude Code) case, the deliverables are:

1. **`.entire/settings.json`** — committed repo enablement (`enabled: true`,
   `absolute_git_hook_path: true`). This is what marks the repo as Entire-enabled.
2. **`.entire/.gitignore`** — ignores Entire's local-only scratch dirs.
3. **Agent hooks** in the agent's committed config (`.claude/settings.json` for
   Claude Code) — the `entire hooks claude-code <event>` lifecycle wiring, plus a
   `SessionStart` step that runs the setup script below.
4. **`scripts/setup-entire.sh`** — the idempotent, run-every-session bootstrap:
   install the CLI if missing, put it on PATH, re-arm the git hooks.
5. **A `.gitignore` allowance** so `.entire/` (minus its own ignores) is committed.

Templates cover the mechanics; recipes cover the per-agent config shape.

| Piece | Template | Notes |
|-------|----------|-------|
| Session bootstrap script | `templates/setup-entire.sh` | Generalized; set `ENTIRE_AGENT` (default `claude-code`) |
| Repo enablement config | `templates/entire-settings.json` | → commit as `.entire/settings.json` |
| Entire local-scratch ignores | `templates/entire-gitignore` | → commit as `.entire/.gitignore` |
| Claude Code hooks block | `templates/claude-code-settings.json` | → merge into `.claude/settings.json` |

| Agent | Recipe |
|-------|--------|
| Claude Code (Claude Code on the web, Cursor Cloud Agent) | `recipes/claude-code.md` |

Claude Code is the tested path. The mechanics generalize to other agents Entire
supports, but those aren't covered here — and most don't offer a hosted cloud
agent anyway.

Make a todo list and work through the steps below.

## Workflow

### 1. Detect the environment and the agent

- **Which agent** will run in the VM? Check for the agent's config dir/marker —
  `.claude/` (Claude Code) is the tested case, and the one `recipes/claude-code.md`
  covers. Entire's CLI also supports `codex`, `copilot-cli`, `cursor`,
  `factoryai-droid`, `gemini`, `opencode`, and `pi`, but those paths are untested here.
- **Where is it running?** Confirm it's a **remote/ephemeral** environment (Claude
  Code on the web, Cursor Cloud Agent, a dev VM). If the agent is local on the
  human's own machine, they likely just want `entire enable` once — the
  re-arm-every-session machinery is unnecessary. Confirm before doing the full setup.
- **Is it a git repo?** Entire capture is git-anchored. `git rev-parse --git-dir`
  must succeed. If not, stop — there's nothing to checkpoint against.

### 2. Confirm scope with the user

Pin down:

- **Capture mode**: local-only (no login) vs. platform sync (needs `ENTIRE_TOKEN`
  as an env secret). Default to local-only; mention platform sync as an add-on.
- **Which agent(s)** to enable (usually one; Entire can enable several).
- **Commit behavior**: whether to commit the `.entire/` config + agent hooks now,
  or leave them staged for the user to review. Default: create the files, then ask
  before committing (see step 7).

### 3. Drop in the repo enablement config

- Copy `templates/entire-settings.json` → `.entire/settings.json`.
- Copy `templates/entire-gitignore` → `.entire/.gitignore`.

`absolute_git_hook_path: true` makes the installed git hooks call the `entire`
binary by **full path**, so they work in later tool shells regardless of PATH —
important on cloud VMs where each tool invocation may be a fresh shell.

### 4. Wire the agent hooks

Follow the recipe for your agent. For Claude Code, merge
`templates/claude-code-settings.json` into `.claude/settings.json`. Two things
matter:

- The lifecycle hooks each **guard on the CLI existing** (`command -v entire ||
  exit 0`) so a VM without Entire installed doesn't fail the session.
- The `SessionStart` array runs `scripts/setup-entire.sh` **before** the
  `entire hooks ... session-start` call, so the CLI is installed and the git hooks
  are armed by the time the session-start hook fires.

### 5. Drop in the session bootstrap script

Copy `templates/setup-entire.sh` → `scripts/setup-entire.sh` (or wherever the repo
keeps scripts) and `chmod +x` it. Customize only if needed:

- `ENTIRE_AGENT` — defaults to `claude-code`; set to the agent you're enabling for
  the first-time-enable branch.
- Install method — the template uses `go install` (see gotcha below). If the VM
  has network access to GitHub releases, `install.sh` also works; keep `go install`
  for Claude Code on the web / restricted proxies.

The script is **idempotent and never fails the session** — every error is logged
and skipped. It:

1. Installs `entire` + `git-remote-entire` via `go install` if missing.
2. Appends `~/.local/bin` to `~/.bashrc`/`~/.profile` so later tool shells find it.
3. Re-arms the git hooks: `entire configure --force --absolute-git-hook-path` when
   `.entire/settings.json` is present, else a first-time `entire enable --agent <a>`.
4. Reports platform-sync status based on `ENTIRE_TOKEN`.

### 6. Ensure `.entire/` is committable

Confirm the repo's top-level `.gitignore` doesn't exclude `.entire/`. The
committed pieces are `.entire/settings.json` and `.entire/.gitignore`; everything
else under `.entire/` (tmp, metadata, logs, local redactors, `settings.local.json`)
is ignored by the `.entire/.gitignore` you just added.

### 7. Validate end-to-end

Non-negotiable — without validation you don't know the wiring survives a fresh VM.

1. **Run the bootstrap** as the session would:
   ```bash
   ENTIRE_AGENT=claude-code bash scripts/setup-entire.sh
   ```
   Expect: `entire` on PATH afterward (`command -v entire`), git hooks present
   (`ls .git/hooks/commit-msg` and `grep -q entire .git/hooks/commit-msg`).
2. **Check status**: `entire status` (and `entire version`) should report the repo
   as enabled. `entire auth status` if you set a token.
3. **Prove a checkpoint** (optional but strongest): make a throwaway commit in a
   scratch branch and confirm a checkpoint lands — `git log entire/checkpoints/v1`
   gains an entry, or the commit message carries the `Entire-Checkpoint` trailer.
   Clean up the scratch commit afterward.
4. **Lint the artifacts**: `bash -n scripts/setup-entire.sh` (and `shellcheck` if
   available); JSON-validate `.entire/settings.json` and `.claude/settings.json`.

### 8. Commit and push

If the user is on a feature branch and asked to commit, stage the config +
hooks + script explicitly (not `git add .`) and commit. Default branch — ask
first. Never commit `ENTIRE_TOKEN` or anything under the `.entire/` ignore list.

## Gotchas

- **`go install`, not `install.sh`, on restricted proxies.** Claude Code on the
  web's GitHub proxy blocks release-asset downloads for out-of-scope repos, so the
  `install.sh` path (which pulls GitHub releases) fails. `go install
  github.com/entireio/cli/cmd/entire@latest` uses the Go module proxy and works.
  First `go install` also fetches a Go toolchain (~1 min). If `go` itself is
  missing, the script logs and skips — capture is simply off that session.
- **Git hooks are not version-controlled.** `.git/hooks` is empty on every fresh
  VM, so the git-side capture must be re-armed **every session** via
  `entire configure`. This is the whole reason for the `SessionStart` bootstrap —
  committing the hooks isn't possible. Agent hooks, by contrast, live in committed
  config and are already armed.
- **Order in `SessionStart` matters.** `setup-entire.sh` must run before the
  `entire hooks ... session-start` call; otherwise the session-start hook fires
  before the CLI exists.
- **Cursor Cloud Agent doesn't run SessionStart hooks.** If the agent is Cursor's
  cloud runner, the `.claude/settings.json` SessionStart step won't fire — run
  `scripts/setup-entire.sh` explicitly (or from the agent's own startup mechanism).
- **`absolute_git_hook_path: true` is deliberate.** Cloud VMs spawn each tool call
  in a fresh shell; a PATH-relative hook can miss `entire`. Absolute paths dodge that.
- **Platform sync needs a real token.** `ENTIRE_TOKEN` must be a bearer minted by
  `entire auth token` on a logged-in machine, provided as an **environment secret**
  — never commit it. Without it, capture is local-git-only, which is fully
  functional (checkpoints live on the local `entire/checkpoints/v1` ref).
- **Don't fail the session.** The bootstrap is defensive on purpose: not-a-repo,
  no `go`, install failure, or missing config all log-and-skip with `exit 0`. Keep
  it that way — capture is an enhancement, not a hard dependency of the agent's run.
- **`pkill -f entire` foot-gun.** In a shared VM, a broad `pkill -f entire` can
  match the agent's own command line. Target PIDs, not patterns.

## What this skill is NOT for

- Rendering/consuming Entire data in an app's UI (graph overlays, detail panes,
  resume buttons, viewer tabs) — that's product feature work.
- Screenshot/video capture of a UI — use a headless-capture style skill.
- Generic MCP setup unrelated to Entire capture.
