#!/bin/bash
# Setup Stably Orca: Arch scanned AUR / Ubuntu verified self-updating AppImage.
# The launcher is stably-orca; Arch's orca package is the GNOME screen reader.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Orca"

ensure_desktop_ide orca || exit 1
print_info_message "Launch with stably-orca or orca-ide (never the screen-reader command orca)"
print_tool_setup_complete "Orca"
