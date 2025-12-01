#!/bin/bash

# --------------------------
# Setup Nerd Fonts for Arch Linux
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

print_tool_setup_start "Fonts"

# --------------------------
# Install Nerd Fonts via AUR
# --------------------------

# Map font names to AUR package names
# Update this associative array to install different fonts if desired
declare -A NERD_FONTS=(
    ["Meslo"]="ttf-meslo-nerd"
    ["Ubuntu"]="ttf-ubuntu-nerd"
    ["FiraCode"]="ttf-firacode-nerd"
    ["JetBrainsMono"]="ttf-jetbrains-mono-nerd"
    ["Hack"]="ttf-hack-nerd"
)

print_info_message "Installing Nerd Fonts from official Arch repositories"

# Batch check which fonts need to be installed
FONTS_TO_INSTALL=()
for FONT_NAME in "${!NERD_FONTS[@]}"; do
    PACKAGE_NAME="${NERD_FONTS[$FONT_NAME]}"
    if pacman -Q "$PACKAGE_NAME" &> /dev/null; then
        print_info_message "$FONT_NAME Nerd Font already installed"
    else
        FONTS_TO_INSTALL+=("$PACKAGE_NAME")
    fi
done

# Batch install all missing fonts
FONTS_UPDATED=false
if [ ${#FONTS_TO_INSTALL[@]} -gt 0 ]; then
    print_info_message "Installing ${#FONTS_TO_INSTALL[@]} font package(s): ${FONTS_TO_INSTALL[*]}"
    if sudo pacman -S --needed --noconfirm "${FONTS_TO_INSTALL[@]}"; then
        print_success_message "Fonts installed successfully"
        FONTS_UPDATED=true
    else
        print_error_message "Some fonts failed to install"
    fi
else
    print_info_message "All Nerd Fonts are already installed"
fi

# --------------------------
# Refresh Font Cache
# --------------------------

# Refresh font cache if new fonts were installed
if [ "$FONTS_UPDATED" = true ]; then
    print_info_message "Fonts were installed. Refreshing font cache."
    fc-cache -f # add -v for verbose output
    print_info_message "Font cache refreshed successfully"
else
    print_info_message "No new fonts were installed. Skipping font cache refresh."
fi

print_tool_setup_complete "Fonts"
