#!/bin/bash

# --------------------------
# Setup Zoom for Arch Linux
# --------------------------
# Zoom is installed from the AUR (Arch User Repository).
# The AUR package provides the official Zoom client.
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

print_tool_setup_start "Zoom"

# --------------------------
# Install Zoom via AUR
# --------------------------

# Check if Zoom is already installed
if command -v zoom &> /dev/null; then
    print_info_message "Zoom is already installed. Skipping installation."
    print_info_message "Installed version: $(pacman -Q zoom 2>/dev/null | awk '{print $2}')"
else
    print_info_message "Installing Zoom from AUR"

    # Install Zoom from AUR
    yay -S --noconfirm --needed zoom

    if command -v zoom &> /dev/null; then
        print_info_message "Zoom installed successfully"
        print_info_message "You can launch Zoom from your application menu or run: zoom"
        echo ""
        print_info_message "To update Zoom in the future, run:"
        print_info_message "  yay -S zoom"
        print_info_message "Or update all packages with:"
        print_info_message "  yay -Syu"
    else
        print_error_message "Zoom installation failed"
        print_info_message "You can manually install with: yay -S zoom"
    fi
fi

print_tool_setup_complete "Zoom"

