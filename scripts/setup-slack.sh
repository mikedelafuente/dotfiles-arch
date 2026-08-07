#!/bin/bash

# --------------------------
# Setup Slack for Arch Linux
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

print_tool_setup_start "Slack"

if command -v slack &> /dev/null; then
    print_info_message "Slack is already installed. Skipping installation."
else
    print_info_message "Installing Slack from AUR (slack-desktop)"
    ensure_yay_pkgs slack-desktop

    if command -v slack &> /dev/null; then
        print_success_message "Slack installed successfully"
        print_info_message "You can launch Slack from your application menu or run: slack"
    else
        print_error_message "Slack installation failed"
        print_info_message "You can manually install with: yay -S slack-desktop"
    fi
fi

print_tool_setup_complete "Slack"
