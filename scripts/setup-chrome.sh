#!/bin/bash

# --------------------------
# Setup Google Chrome for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Google Chrome"

if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
  print_info_message "Google Chrome is already installed. Skipping installation."
else
  print_info_message "Installing Google Chrome from AUR (google-chrome)"
  yay -S --needed --noconfirm google-chrome

  if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
    print_success_message "Google Chrome installed successfully"
  else
    print_error_message "Google Chrome installation failed"
    print_info_message "You can manually install with: yay -S google-chrome"
  fi
fi

print_tool_setup_complete "Google Chrome"
