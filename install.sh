#!/usr/bin/env bash
#
# install.sh — build the Meridian proxy + opencode-with-claude plugin from the
# pinned submodules and register the plugin with OpenCode.
#
# Reproduces this resolution chain (all off this repo, nothing in /tmp):
#
#   OpenCode plugin cache ──symlink──▶ opencode-with-claude/   (this repo)
#        └─ node_modules/@rynfar/meridian ──npm link──▶ meridian/   (this repo)
#
# Usage:
#   ./install.sh            build, link, and register the plugin
#   ./install.sh --test     also run meridian's test suite after building
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TESTS=0
[ "${1:-}" = "--test" ] && RUN_TESTS=1

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
command -v node >/dev/null 2>&1 || die "node is required"
command -v npm  >/dev/null 2>&1 || die "npm is required"
if ! command -v bun >/dev/null 2>&1; then
  if [ -x "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
  else
    die "bun is required to build meridian — install from https://bun.sh"
  fi
fi
log "Toolchain: node $(node -v), npm $(npm -v), bun $(bun -v)"

# --- submodules ------------------------------------------------------------
log "Syncing submodules..."
git -C "$ROOT" submodule update --init --recursive

# --- meridian (proxy) ------------------------------------------------------
log "Building meridian (proxy)..."
cd "$ROOT/meridian"
bun install
bun run build
[ -f dist/server.js ] || die "meridian build did not produce dist/server.js"
npm link >/dev/null 2>&1
log "Linked @rynfar/meridian globally -> $ROOT/meridian"

if [ "$RUN_TESTS" = "1" ]; then
  log "Running meridian tests (pre-existing unrelated failures are expected)..."
  bun run test || warn "meridian test suite reported failures (see output above)"
fi

# --- plugin ----------------------------------------------------------------
log "Building opencode-with-claude (plugin)..."
cd "$ROOT/opencode-with-claude"
npm install
npm link @rynfar/meridian >/dev/null 2>&1
npm run build
[ -f dist/index.js ] || die "plugin build did not produce dist/index.js"
npm link >/dev/null 2>&1
log "Linked opencode-with-claude globally -> $ROOT/opencode-with-claude"

# --- register with OpenCode ------------------------------------------------
if command -v opencode >/dev/null 2>&1; then
  log "Registering plugin with OpenCode (refreshing cache)..."
  opencode plugin opencode-with-claude --force || \
    warn "'opencode plugin' returned non-zero — the plugin may still load via opencode.json"
else
  warn "opencode CLI not on PATH — skipping cache registration"
fi

# --- opencode.json check ---------------------------------------------------
CFG="$HOME/.config/opencode/opencode.json"
if [ -f "$CFG" ] && grep -q '"opencode-with-claude"' "$CFG"; then
  log "opencode.json already lists the plugin"
else
  warn "Plugin not found in $CFG — add it manually:"
  cat <<'EOF'

    {
      "plugin": ["opencode-with-claude"],
      "provider": {
        "anthropic": {
          "options": { "baseURL": "http://127.0.0.1:3456", "apiKey": "dummy" }
        }
      }
    }
EOF
fi

cat <<EOF

Done. Restart OpenCode completely (quit ALL windows) to load the rebuilt proxy + plugin.

  Verify after restart:
    curl -s http://127.0.0.1:3456/v1/models | head -c 200

EOF
