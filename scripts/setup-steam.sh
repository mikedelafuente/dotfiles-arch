#!/bin/bash

# --------------------------
# Setup Steam for Arch Linux
# --------------------------
# Steam is installed from the multilib repository, which provides the official
# Steam package for Arch. This is the recommended method because:
# - Official Steam package maintained for Arch
# - Better integration with system libraries and drivers
# - Optimal gaming performance (no containerization overhead)
# - Standard Arch package management
#
# Note: Requires multilib repository to be enabled.
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

print_tool_setup_start "Steam"

# --------------------------
# Enable Multilib Repository
# --------------------------

# Check if multilib repository is enabled
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    print_info_message "Enabling multilib repository"
    sudo sed -i '/^#\[multilib\]/,/^#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
    sudo pacman -Sy --noconfirm
    print_info_message "Multilib repository enabled"
else
    print_info_message "Multilib repository already enabled"
fi

# --------------------------
# Install Steam
# --------------------------

# Check if Steam is already installed
if ! command -v steam &> /dev/null; then
    print_info_message "Installing Steam from multilib repository"

    # Install Steam
    sudo pacman -S --needed --noconfirm steam

    print_info_message "Steam installed successfully"
    print_info_message "You can launch Steam from your application menu or run: steam"
    echo ""
    print_info_message "To update Steam in the future, run:"
    print_info_message "  sudo pacman -S steam"
    print_info_message "Or update all packages with:"
    print_info_message "  sudo pacman -Syu"
    echo ""
    print_info_message "Note: Steam may require additional setup for optimal gaming:"
    print_info_message "  - Enable Proton for Windows games in Steam settings"
    print_info_message "  - Install GPU drivers if needed (NVIDIA/AMD)"
    print_info_message "  - Consider enabling Steam Play for all titles"
else
    print_info_message "Steam is already installed. Skipping installation."
    print_info_message "Installed version: $(pacman -Q steam 2>/dev/null || echo 'unknown')"
fi

print_tool_setup_complete "Steam"

