#!/bin/bash

# --------------------------
# Setup Spotify for Arch Linux
# --------------------------
# Spotify is installed from the AUR (Arch User Repository).
# The AUR package provides:
# - Easy updates through yay or other AUR helpers
# - Native integration with the system
# - Better performance without containerization overhead
# - Standard Arch package management
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

print_tool_setup_start "Spotify"

# --------------------------
# Install Spotify via AUR
# --------------------------

# Check if Spotify is already installed
if command -v spotify &> /dev/null; then
    print_info_message "Spotify is already installed. Skipping installation."
    print_info_message "Installed version: $(pacman -Q spotify 2>/dev/null | awk '{print $2}')"
else
    print_info_message "Installing Spotify from AUR"

    # Install Spotify from AUR
    yay -S --noconfirm --needed spotify

    if command -v spotify &> /dev/null; then
        print_info_message "Spotify installed successfully"
        print_info_message "You can launch Spotify from your application menu or run: spotify"
        echo ""
        print_info_message "To update Spotify in the future, run:"
        print_info_message "  yay -S spotify"
        print_info_message "Or update all packages with:"
        print_info_message "  yay -Syu"
    else
        print_error_message "Spotify installation failed"
        print_info_message "You can manually install with: yay -S spotify"
    fi
fi

print_tool_setup_complete "Spotify"

