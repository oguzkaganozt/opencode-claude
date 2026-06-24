#!/usr/bin/env bash
#
# install.sh — one-line install of oguzkaganozt/opencode-claude.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash
#
set -euo pipefail

REPO="${OPENCODE_CLAUDE_REPO:-oguzkaganozt/opencode-claude}"
REF="${OPENCODE_CLAUDE_REF:-main}"
DIR="${OPENCODE_CLAUDE_DIR:-$HOME/.opencode-claude}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"
command -v node >/dev/null 2>&1 || die "node is required"

clone_with_gh() {
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    log "using gh (authenticated as $(gh api user --jq .login 2>/dev/null))"
    gh repo clone "$REPO" "$DIR" -- --branch "$REF" --recurse-submodules --depth 1
    return 0
  fi
  return 1
}

clone_with_token() {
  [ -n "${OPENCODE_CLAUDE_TOKEN:-}" ] || [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ] || return 1
  local token="${OPENCODE_CLAUDE_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
  log "using token-authenticated git clone"
  mkdir -p "$(dirname "$DIR")"
  git clone "https://x-access-token:${token}@github.com/${REPO}.git" "$DIR" \
    --branch "$REF" --recurse-submodules --depth 1
}

clone_public() {
  log "using public git clone"
  mkdir -p "$(dirname "$DIR")"
  git clone "https://github.com/${REPO}.git" "$DIR" \
    --branch "$REF" --recurse-submodules --depth 1
}

if [ -d "$DIR/.git" ]; then
  log "Existing install at $DIR — updating"
  cd "$DIR"

  expected="https://github.com/${REPO}.git"
  current="$(git remote get-url origin 2>/dev/null || true)"
  if [ "$current" != "$expected" ]; then
    warn "Remote mismatch:"
    warn "  current:  $current"
    warn "  expected: $expected"
    printf 'Re-point origin? [y/N] '
    read -r ans
    case "$ans" in y|Y|yes|YES) git remote set-url origin "$expected" ;; *) die "aborted" ;; esac
  fi

  git fetch --tags --prune origin 2>/dev/null || true
  git checkout -- . 2>/dev/null || true
  git clean -fdx 2>/dev/null || true
  git checkout "$REF"
  git pull --ff-only origin "$REF" 2>/dev/null || warn "fast-forward pull failed — leaving tree as-is"
  git submodule update --init --recursive
else
  log "Cloning $REPO @ $REF into $DIR"
  clone_with_gh || clone_with_token || clone_public || die "clone failed"
fi

cd "$DIR"
log "Running local installer ..."
chmod +x scripts/install-local.sh
exec ./scripts/install-local.sh "$@"
