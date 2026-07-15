# Recipe: Claude Code (Claude Code on the web, Cursor Cloud Agent)

Claude Code is the reference agent for this skill. It reads hooks from
`.claude/settings.json`, which is **committed**, so the lifecycle hooks are armed
the moment the agent starts on a fresh VM. The one thing that can't be committed —
the git hooks in `.git/hooks` — is re-armed by the `SessionStart` bootstrap.

## Files

| Source template | Destination | Committed? |
|-----------------|-------------|------------|
| `templates/entire-settings.json` | `.entire/settings.json` | yes |
| `templates/entire-gitignore` | `.entire/.gitignore` | yes |
| `templates/claude-code-settings.json` | merge into `.claude/settings.json` | yes |
| `templates/setup-entire.sh` | `scripts/setup-entire.sh` (chmod +x) | yes |

## Merging the hooks

`.claude/settings.json` may already exist with other hooks/permissions. Merge, don't
overwrite:

- Drop the leading `"//"` documentation key from the template.
- For each hook event (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `Stop`, `SessionEnd`), append the Entire command objects to the
  existing arrays rather than replacing them.
- In `SessionStart`, put `$CLAUDE_PROJECT_DIR/scripts/setup-entire.sh` **before**
  the `entire hooks claude-code session-start` command. Order is load-bearing: the
  bootstrap installs the CLI and arms the git hooks that the session-start hook and
  later commits depend on.
- Keep the `permissions.deny` entry `Read(./.entire/metadata/**)` so the agent
  can't read Entire's own metadata scratch.

## Environment specifics

- **Claude Code on the web** — Linux containers; `SessionStart` hooks run. The
  bootstrap's `go install` path is required here because the GitHub proxy blocks
  release-asset downloads for out-of-scope repos (so `install.sh` fails). Provide
  `ENTIRE_TOKEN` as an environment secret if platform sync is wanted.
- **Cursor Cloud Agent** — `CURSOR_AGENT=1`. **SessionStart hooks do NOT run here.**
  The `.claude/settings.json` bootstrap step won't fire, so either:
  - run `bash scripts/setup-entire.sh` explicitly at the start of the task, or
  - hook it into Cursor's own startup mechanism (e.g. an environment/setup script
    the Cloud Agent runs).
  Everything downstream (git hooks, checkpoints) works the same once the CLI is on
  PATH and `entire configure` has run.

## Validate

```bash
# Simulate the session bootstrap
ENTIRE_AGENT=claude-code bash scripts/setup-entire.sh

command -v entire                              # CLI on PATH
grep -q entire .git/hooks/commit-msg           # git hooks armed
entire status                                  # repo reported enabled
# Optional strongest proof: throwaway commit on a scratch branch,
# then confirm entire/checkpoints/v1 advanced:
git log --oneline entire/checkpoints/v1 | head
```
