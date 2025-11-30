#!/bin/bash

# --------------------------
# Setup Postman for Arch Linux
# --------------------------
# Postman is installed from the AUR package 'postman-bin'.
# This is the official Postman binary repackaged for Arch Linux.
#
# This installation method:
# - Uses the official Postman distribution from AUR
# - Automatically handles installation, desktop entry, and updates
# - Provides the full-featured version
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

print_tool_setup_start "Postman"

# --------------------------
# Install Postman via AUR
# --------------------------

# Check if Postman is already installed
if command -v postman &> /dev/null; then
    print_info_message "Postman is already installed. Skipping installation."
else
    print_info_message "Installing Postman from AUR (postman-bin)"
    yay -S --noconfirm --needed postman-bin

    # Verify installation
    if command -v postman &> /dev/null; then
        print_info_message "Postman installed successfully"
        print_info_message "You can launch Postman from your application menu or run: postman"
    else
        print_error_message "Postman installation failed"
        print_info_message "You can manually install with: yay -S postman-bin"
    fi
fi

print_tool_setup_complete "Postman"

