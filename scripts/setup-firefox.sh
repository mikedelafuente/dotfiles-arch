#!/bin/bash

# --------------------------
# Setup Firefox for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Firefox"

if command -v firefox &>/dev/null; then
  print_info_message "Firefox is already installed. Skipping installation."
else
  print_info_message "Installing Firefox via pacman"
  sudo pacman -S --needed --noconfirm firefox

  if command -v firefox &>/dev/null; then
    print_success_message "Firefox installed successfully"
  else
    print_error_message "Firefox installation failed"
  fi
fi

print_tool_setup_complete "Firefox"
