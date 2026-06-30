#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TESTS=0
[ "${1:-}" = "--test" ] && RUN_TESTS=1

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v node >/dev/null 2>&1 || die "node is required"
command -v npm  >/dev/null 2>&1 || die "npm is required"
if ! command -v bun >/dev/null 2>&1; then
  if [ -x "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
  else
    die "bun is required — install from https://bun.sh"
  fi
fi
log "toolchain: node $(node -v), npm $(npm -v), bun $(bun -v)"

log "syncing submodules..."
git -C "$ROOT" submodule update --init --recursive

log "building meridian (proxy)..."
cd "$ROOT/meridian"
bun install
bun run build
[ -f dist/server.js ] || die "meridian build failed"

if [ "$RUN_TESTS" = "1" ]; then
  log "running meridian tests..."
  bun run test || warn "meridian tests reported failures"
fi

log "building plugin..."
cd "$ROOT/plugin"
npm install
npm run build
[ -f dist/index.js ] || die "plugin build failed"

# --- opencode.json wiring -------------------------------------------------
CFG="${OPENCODE_CONFIG_PATH:-$HOME/.config/opencode/opencode.json}"
PLUGIN_ENTRY="$ROOT/plugin/dist/index.js"

log "wiring OpenCode config -> $CFG"
mkdir -p "$(dirname "$CFG")"

if [ -f "$CFG" ]; then
  BACKUP="$CFG.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CFG" "$BACKUP"
  log "backed up existing config -> $BACKUP"
fi

OPENCODE_CONFIG_PATH="$CFG" PLUGIN_ENTRY="$PLUGIN_ENTRY" node <<'NODE'
const fs = require("node:fs");

const configPath = process.env.OPENCODE_CONFIG_PATH;
const pluginEntry = process.env.PLUGIN_ENTRY;

let config = {};
if (fs.existsSync(configPath)) {
  const raw = fs.readFileSync(configPath, "utf8").trim();
  if (raw) {
    try {
      config = JSON.parse(raw);
    } catch (error) {
      console.error(`Failed to parse ${configPath}: ${error.message}`);
      process.exit(1);
    }
  }
}

const existingPlugins = Array.isArray(config.plugin) ? config.plugin : [];
const keepPlugin = (entry) => {
  if (typeof entry !== "string") return true;
  if (entry === pluginEntry) return false;
  if (entry === "opencode-with-claude") return false;
  if (entry.includes("/opencode-with-claude/")) return false;
  if (entry.includes("/opencode-claude/plugin/dist/index.js")) return false;
  return true;
};

config.plugin = [pluginEntry, ...existingPlugins.filter(keepPlugin)];
config.provider = config.provider && typeof config.provider === "object" ? config.provider : {};
const anthropic = config.provider.anthropic && typeof config.provider.anthropic === "object"
  ? config.provider.anthropic
  : {};

config.provider.anthropic = {
  ...anthropic,
  options: {
    ...(anthropic.options && typeof anthropic.options === "object" ? anthropic.options : {}),
    baseURL: "http://127.0.0.1:3456",
    apiKey: "dummy",
  },
};

fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
NODE

log "OpenCode config OK -> $CFG"

cat <<EOF

Done. OpenCode is configured automatically.

Restart OpenCode completely. Verify after restart:
    curl -s http://127.0.0.1:3456/v1/models | head -c 200

EOF
