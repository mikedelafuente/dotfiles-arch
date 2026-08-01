#!/bin/bash

# -------------------------
# GitHub CLI Setup for Arch Linux
# -------------------------

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

print_tool_setup_start "GitHub CLI"

if command -v gh &> /dev/null; then
    print_info_message "GitHub CLI (gh) is already installed."
    gh --version
else
    print_action_message "Installing GitHub CLI (gh)..."
    sudo pacman -S --needed --noconfirm github-cli

    if command -v gh &> /dev/null; then
        print_success_message "GitHub CLI installed successfully!"
        gh --version
    else
        print_error_message "Failed to install GitHub CLI"
        exit 1
    fi
fi

print_info_message ""
print_info_message "Next step: authenticate with  gh auth login"

print_tool_setup_complete "GitHub CLI"
