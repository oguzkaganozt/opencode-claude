#!/usr/bin/env bash
set -euo pipefail

REPO="${OPENCODE_CLAUDE_REPO:-oguzkaganozt/opencode-claude}"
REF="${OPENCODE_CLAUDE_REF:-main}"
DIR="${OPENCODE_CLAUDE_DIR:-$HOME/.opencode-claude}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v git  >/dev/null 2>&1 || die "git is required"
command -v node >/dev/null 2>&1 || die "node is required"

clone_with_gh() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    log "using gh (authenticated as $(gh api user --jq .login 2>/dev/null))"
    gh repo clone "$REPO" "$DIR" -- --branch "$REF" --recurse-submodules --depth 1
    return 0
  fi
  return 1
}

clone_public() {
  log "cloning $REPO @ $REF"
  mkdir -p "$(dirname "$DIR")"
  git clone "https://github.com/${REPO}.git" "$DIR" \
    --branch "$REF" --recurse-submodules --depth 1
}

if [ -d "$DIR/.git" ]; then
  log "existing install at $DIR — updating"
  cd "$DIR"
  git fetch --tags --prune origin 2>/dev/null || true
  git checkout -- . 2>/dev/null || true
  git clean -fdx 2>/dev/null || true
  git checkout "$REF"
  git pull --ff-only origin "$REF" 2>/dev/null || warn "fast-forward pull failed"
  git submodule update --init --recursive
else
  clone_with_gh || clone_public || die "clone failed"
fi

cd "$DIR"
log "running installer ..."
chmod +x scripts/install-local.sh
exec ./scripts/install-local.sh "$@"
