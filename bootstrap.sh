#!/usr/bin/env bash
# Compatibility alias. Prefer install.sh.
set -euo pipefail
curl -fsSL https://raw.githubusercontent.com/oguzkaganozt/opencode-claude/main/install.sh | bash -s -- "$@"
