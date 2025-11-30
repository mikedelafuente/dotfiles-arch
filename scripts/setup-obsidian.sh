#!/bin/bash

# --------------------------
# Setup Obsidian for Arch Linux
# --------------------------
# Obsidian is installed from the AUR (Arch User Repository).
# The AUR package provides:
# - Easy updates through yay or other AUR helpers
# - Native integration with the system
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

print_tool_setup_start "Obsidian"

# --------------------------
# Install Obsidian via AUR
# --------------------------

# Check if Obsidian is already installed
if command -v obsidian &> /dev/null; then
    print_info_message "Obsidian is already installed. Skipping installation."
    print_info_message "Installed version: $(pacman -Q obsidian 2>/dev/null | awk '{print $2}')"
else
    print_info_message "Installing Obsidian from AUR"

    # Install Obsidian from AUR
    yay -S --noconfirm --needed obsidian

    if command -v obsidian &> /dev/null; then
        print_info_message "Obsidian installed successfully"
        print_info_message "You can launch Obsidian from your application menu or run: obsidian"
        echo ""
        print_info_message "To update Obsidian in the future, run:"
        print_info_message "  yay -S obsidian"
        print_info_message "Or update all packages with:"
        print_info_message "  yay -Syu"
    else
        print_error_message "Obsidian installation failed"
        print_info_message "You can manually install with: yay -S obsidian"
    fi
fi

print_tool_setup_complete "Obsidian"

