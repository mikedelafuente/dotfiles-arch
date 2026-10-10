#!/bin/bash

# -------------------------
# Link shared dotfiles for Arch / Ubuntu 26.04
# Stage installed copies, then link stable deployment paths into the home directory
# -------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# Deployment stages a complete copy before any checkout links are replaced.
# Profile selection remains owned by bootstrap/sync; linking is shared.
REPO_ROOT="$(cd -- "$CURRENT_FILE_DIR/.." && pwd)"
ensure_local_gitconfig || exit 1
if [[ -L "$USER_HOME_DIR/.local/share/workstation/config" ]]; then
  exec python3 "$DF_SCRIPT_DIR/deployment.py" deploy
fi
exec python3 "$DF_SCRIPT_DIR/deployment.py" deploy --source "$REPO_ROOT"
