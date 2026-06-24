#!/usr/bin/env bash
#
# install.sh — build Meridian and the opencode-claude plugin from source.
#
# Pipeline:
#   1. sync meridian submodule (fork/init)
#   2. bun install + bun build meridian
#   3. npm install + npm build plugin (file:../meridian is wired in package.json)
#   4. print the opencode.json path the user must paste in
#
# No global npm links, no `opencode plugin` registration, no cache symlink.
# OpenCode loads the plugin from a local path; meridian is resolved through
# the plugin's own node_modules via the `file:../meridian` dep.
#
# Usage:
#   ./install.sh            build everything
#   ./install.sh --test     also run meridian's test suite
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
log "Meridian OK -> $ROOT/meridian/dist/server.js"

if [ "$RUN_TESTS" = "1" ]; then
  log "Running meridian tests (pre-existing unrelated failures are expected)..."
  bun run test || warn "meridian test suite reported failures (see output above)"
fi

# --- plugin ----------------------------------------------------------------
log "Building opencode-claude plugin..."
cd "$ROOT/plugin"
npm install
npm run build
[ -f dist/index.js ] || die "plugin build did not produce dist/index.js"
log "Plugin OK -> $ROOT/plugin/dist/index.js"

# --- opencode.json hint ---------------------------------------------------
CFG="$HOME/.config/opencode/opencode.json"
PLUGIN_ENTRY="$ROOT/plugin/dist/index.js"

cat <<EOF

Done. Two final manual steps (one-time):

1. Wire the plugin into your opencode config:

       $CFG

   Replace the existing opencode-with-claude entry (or add one) with the
   absolute path to the built plugin:

       "plugin": [
         "$PLUGIN_ENTRY"
       ]

   If your config doesn't yet point at the proxy, also add the provider
   block (port defaults to 3456):

       "provider": {
         "anthropic": {
           "options": { "baseURL": "http://127.0.0.1:3456", "apiKey": "dummy" }
         }
       }

2. Restart OpenCode completely (quit ALL windows). The plugin's plugin.config
   hook starts the Meridian proxy on startup, so a full restart is required.

   Verify after restart:
       curl -s http://127.0.0.1:3456/v1/models | head -c 200

EOF
