#!/bin/bash
# GNOME Wayland dictation: verified native/release owners and direct dotool typing.
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start 'Voxtype'
ensure_voxtype setup || exit 1
print_info_message 'Super+T toggles dictation; capture, typing and inference runtime remain unverified'
print_tool_setup_complete 'Voxtype'
