#!/bin/bash

# --------------------------
# Setup Discord for Arch Linux
# --------------------------
# Discord is installed from the AUR (Arch User Repository).
# The discord package provides the official Discord client for Arch Linux.
# --------------------------

# --------------------------
# Import Common Header 
# --------------------------

# add header file
CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# source header (uses SCRIPT_DIR and loads lib.sh)
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

print_tool_setup_start "Discord"

# --------------------------
# Install Discord via AUR
# --------------------------

# Check if Discord is already installed
if command -v discord &> /dev/null; then
    print_info_message "Discord is already installed. Skipping installation."
else
    print_info_message "Installing Discord from AUR"

    # Install Discord from AUR
    yay -S --noconfirm --needed discord

    if command -v discord &> /dev/null; then
        print_info_message "Discord installed successfully"
        print_info_message "You can launch Discord from your application menu or run: discord"
    else
        print_error_message "Discord installation failed"
        print_info_message "You can manually install with: yay -S discord"
    fi
fi

print_tool_setup_complete "Discord"

