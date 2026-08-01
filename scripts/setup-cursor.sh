#!/bin/bash

# --------------------------
# Setup Cursor IDE for Arch Linux
# --------------------------

# --------------------------
# Import Common Header
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# --------------------------
# End Import Common Header
# --------------------------

print_tool_setup_start "Cursor IDE"

if command -v cursor &> /dev/null; then
    print_info_message "Cursor is already installed. Skipping installation."
    cursor --version 2>/dev/null || true
else
    print_action_message "Installing Cursor via yay (cursor-bin)"
    if ! command -v yay &> /dev/null; then
        print_error_message "yay is required to install Cursor from the AUR"
        exit 1
    fi
    yay -S --needed --noconfirm cursor-bin
fi

if command -v cursor &> /dev/null; then
    print_success_message "Cursor is available as: $(command -v cursor)"
else
    print_error_message "Cursor installation may have failed"
    exit 1
fi

print_info_message "Settings are linked to ~/.config/Cursor/User/ via link-dotfiles.sh"
print_tool_setup_complete "Cursor IDE"
