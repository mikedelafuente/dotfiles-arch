#!/bin/bash
# Setup Orca, the Stably AI coding IDE, from the scanned AUR package.
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

if pacman -Q stably-orca-bin &>/dev/null; then
  print_info_message "Orca is already installed. Skipping installation."
else
  print_info_message "Installing Orca from AUR (stably-orca-bin)"
  ensure_yay_installed
  ensure_yay_pkgs stably-orca-bin
fi

if ! pacman -Q stably-orca-bin &>/dev/null; then
  print_error_message "Orca installation failed"
  exit 1
fi

print_info_message "Launch Orca from your application menu or run: stably-orca"
print_tool_setup_complete "Orca"
