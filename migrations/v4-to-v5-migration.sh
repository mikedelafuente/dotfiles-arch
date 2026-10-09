#!/bin/bash
# v4 -> v5: stable installed generations; no package/service operations.
set -euo pipefail
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)"
# shellcheck source=/dev/null
source "$CURRENT_FILE_DIR/dotheader.sh"
if [[ -L "$USER_HOME_DIR/.local/share/workstation/config" ]]; then
  # Already activated: interrupted stamping/replay needs no source checkout.
  python3 "$DF_SCRIPT_DIR/deployment.py" status >/dev/null || exit 1
else
  ensure_local_gitconfig || exit 1
  python3 "$DF_SCRIPT_DIR/deployment.py" deploy --source "$(cd -- "$CURRENT_FILE_DIR/.." && pwd)" || exit 1
fi
