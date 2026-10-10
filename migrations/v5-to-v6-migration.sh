#!/bin/bash
# v5 -> v6: source-owned blue/green copies and one backup; no package/service operations.
set -euo pipefail
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)"
# shellcheck source=/dev/null
source "$CURRENT_FILE_DIR/dotheader.sh"
layout="$(python3 "$DF_SCRIPT_DIR/deployment.py" status)" || exit 1
if [[ "$layout" == *'"layout": "legacy"'* ]]; then
  python3 "$DF_SCRIPT_DIR/deployment.py" deploy || exit 1
fi
