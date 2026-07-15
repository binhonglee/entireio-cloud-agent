#!/usr/bin/env bash
# Entire capture setup for cloud/headless coding-agent sessions.
#
# Run this at session start on ephemeral VMs (Claude Code on the web, Cursor
# Cloud Agent, dev VMs). It is idempotent and NEVER fails the session — every
# error is logged and skipped.
#
# What it does, every session:
#   1. Installs the Entire CLI + the `git-remote-entire` helper (via the Go
#      module proxy — the install.sh path pulls GitHub releases, which some
#      cloud-agent GitHub proxies block for out-of-scope repos).
#   2. Puts them on PATH for later tool shells (the committed agent hooks and
#      the git hooks call `entire` by name).
#   3. Re-arms the git hooks in .git/hooks (not version-controlled, so they must
#      be re-installed each session). Agent hooks live in committed config
#      (e.g. .claude/settings.json), so they are already armed at session start.
#
# Local git capture needs no login. For entire.io platform sync, set ENTIRE_TOKEN
# (a bearer from `entire auth token` on a logged-in machine) as an environment
# secret; capture then rides a normal `git commit` + `git push` (the git hooks
# stamp the Entire-Checkpoint trailer and push entire/checkpoints/v1).
#
# Knobs:
#   ENTIRE_AGENT   Agent to enable on first run (default: claude-code). One of:
#                  claude-code codex copilot-cli cursor factoryai-droid gemini
#                  opencode pi
#   ENTIRE_TOKEN   Bearer token for entire.io platform sync (optional).
set -u
log() { printf '[setup-entire] %s\n' "$*" >&2; }

ENTIRE_AGENT="${ENTIRE_AGENT:-claude-code}"

git rev-parse --git-dir >/dev/null 2>&1 || { log "not a git repo; skipping"; exit 0; }

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# 1. Install the CLI + entire:// helper if missing.
if ! command -v entire >/dev/null 2>&1; then
  if ! command -v go >/dev/null 2>&1; then
    log "go not found; cannot install the Entire CLI; skipping"
    exit 0
  fi
  log "installing entire CLI via go install (first run also fetches a Go toolchain; ~1 min)"
  GOBIN="$BIN_DIR" go install github.com/entireio/cli/cmd/entire@latest \
    2>&1 | sed 's/^/[setup-entire] /' >&2 || log "entire install failed"
  GOBIN="$BIN_DIR" go install github.com/entireio/cli/cmd/git-remote-entire@latest \
    2>&1 | sed 's/^/[setup-entire] /' >&2 || log "git-remote-entire install failed"
fi
command -v entire >/dev/null 2>&1 || { log "entire not on PATH after install; skipping"; exit 0; }

# 2. Make entire discoverable in future tool shells (they source the profile).
for rc in "$HOME/.bashrc" "$HOME/.profile"; do
  [ -e "$rc" ] || : > "$rc"
  grep -qF '/.local/bin' "$rc" 2>/dev/null || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
done

# 3. (Re)install the git hooks. The repo is enabled via the committed
#    .entire/settings.json; --absolute-git-hook-path makes the hooks call the
#    binary by full path so they work regardless of PATH.
if [ -f .entire/settings.json ]; then
  entire configure --force --absolute-git-hook-path \
    2>&1 | sed 's/^/[setup-entire] /' >&2 || log "git hook reinstall failed"
else
  # First-time (config not committed yet): full enable for the chosen agent.
  entire enable --agent "$ENTIRE_AGENT" 2>&1 | sed 's/^/[setup-entire] /' >&2 || log "enable failed"
  entire configure --absolute-git-hook-path >/dev/null 2>&1 || true
fi

# 4. Report platform-sync status.
if [ -n "${ENTIRE_TOKEN:-}" ]; then
  entire auth status 2>&1 | sed 's/^/[setup-entire] /' >&2 || true
  log "ENTIRE_TOKEN set -> checkpoints will sync to entire.io on push"
else
  log "ENTIRE_TOKEN not set -> local git capture only (set it as an env secret for platform sync)"
fi
exit 0
