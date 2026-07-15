# Entire Cloud-Agent Capture Setup

A Claude Code skill that wires a repo so that when the agent runs in a **fresh cloud/headless VM** (Claude Code on the web, an SSH'd-in dev VM, …), its session is captured by [Entire](https://entire.io) and linked to Git history as a **checkpoint**, with no manual steps per session.

## What it does

Cloud-agent VMs are **ephemeral and fresh each session**: the `entire` CLI isn't installed, `PATH` isn't set, and `.git/hooks` are empty. This skill sets up the machinery that re-establishes all of that at session start, every time, so every agent session is captured and checkpointed against your Git history automatically.

A checkpoint is created when the agent commits during a session, so checkpoints are naturally keyed to commits and searchable later.

## What it is NOT for

- Building an Entire **viewer / feature** into an application's own UI (graph overlays, detail panes, resume buttons) — that's product work.
- Browser or desktop **screenshot / video** capture.
- Generic MCP setup unrelated to Entire capture.

## How to use it

This is a skill, not a script. Invoke it in Claude Code against the target repo and it walks through detecting the agent, confirming scope, dropping in the config, and validating end-to-end.

It supports two capture modes:

- **Local git capture** (default) — no login. Checkpoints are written as git objects on the `entire/checkpoints/v1` ref in the local repo.
- **Platform sync (entire.io)** — set `ENTIRE_TOKEN` (a bearer from `entire auth token` on a logged-in machine) as an environment secret. Capture then rides a normal `git commit` + `git push`.

## What it produces

The skill drops these artifacts into the target repo:

| Artifact | Purpose |
|----------|---------|
| `.entire/settings.json` | Committed repo enablement — marks the repo as Entire-enabled |
| `.entire/.gitignore` | Ignores Entire's local-only scratch dirs |
| `.claude/settings.json` hooks | Agent lifecycle hooks + a `SessionStart` step that runs the bootstrap |
| `scripts/setup-entire.sh` | Idempotent, run-every-session bootstrap: install the CLI, fix `PATH`, re-arm git hooks |

## Repo layout

- **`SKILL.md`** — the full skill: workflow, gotchas, and the setup contract. Start here for details.
- **`recipes/`** — per-agent config shapes (`claude-code.md`).
- **`templates/`** — the concrete files the skill copies in (bootstrap script, settings, gitignore).

## Links

- [entire.io](https://entire.io)
