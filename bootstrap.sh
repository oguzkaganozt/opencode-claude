#!/usr/bin/env bash
#
# bootstrap.sh — one-line install of oguzkaganozt/opencode-claude (private repo).
#
# The simplest reliable flow against a private GitHub repo is:
#   1. use `gh` to clone (it already has your auth)
#   2. cd in, run install.sh
#
# This script encodes that flow so the user-facing command stays one line.
#
# Usage:
#   gh repo clone oguzkaganozt/opencode-claude ~/.opencode-claude -- --recurse-submodules
#   ~/.opencode-claude/install.sh
#
#   # or, if you want the bootstrap to handle the clone:
#   gh api repos/oguzkaganozt/opencode-claude/contents/bootstrap.sh?ref=main --jq .content \
#     | base64 -d | bash
#
#   # or for public-repo-style curl-pipe (works because no auth is needed):
#   curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/bootstrap.sh | bash
#     (only works if the repo is public; private repos need `gh` or a token)
#
# Env vars (all optional):
#   OPENCODE_CLAUDE_DIR       install directory (default: $HOME/.opencode-claude)
#   OPENCODE_CLAUDE_REF       branch/tag to checkout (default: main)
#   OPENCODE_CLAUDE_REPO      owner/repo (default: oguzkaganozt/opencode-claude)
#   OPENCODE_CLAUDE_TOKEN     PAT for curl | bash against a private repo
#                              (skipped silently if gh is authenticated)
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

# ---------------------------------------------------------------------------
# Three clone paths, in order of preference:
#   1. gh repo clone    (uses existing gh auth — works for private repos)
#   2. git + GH_TOKEN   (uses explicit PAT in env)
#   3. git w/o auth     (only succeeds for public repos)
# ---------------------------------------------------------------------------
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
  log "no gh auth or token found — trying public clone"
  mkdir -p "$(dirname "$DIR")"
  git clone "https://github.com/${REPO}.git" "$DIR" \
    --branch "$REF" --recurse-submodules --depth 1
}

# ---------------------------------------------------------------------------
# Update an existing install (idempotent re-run)
# ---------------------------------------------------------------------------
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
  clone_with_gh || clone_with_token || clone_public || {
    cat <<EOF 1>&2

All three clone paths failed. To install this private repo you need either:

  1. The GitHub CLI (recommended):
       gh auth login --git-protocol https
       then re-run this script

  2. A personal access token in the env:
       export GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
       then re-run this script

EOF
    exit 1
  }
fi

# ---------------------------------------------------------------------------
# Run the real installer
# ---------------------------------------------------------------------------
cd "$DIR"
log "Running install.sh ..."
chmod +x install.sh
exec ./install.sh "$@"
