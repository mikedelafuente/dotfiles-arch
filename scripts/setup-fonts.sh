#!/bin/bash

# --------------------------
# Setup shared UI + Nerd Fonts for Arch Linux
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

print_tool_setup_start "Fonts"

# --------------------------
# System / GNOME UI fonts
# --------------------------
# GNOME 48+ defaults to Adwaita Sans/Mono (adwaita-fonts).
# Noto + Liberation cover generic sans/serif/mono fallbacks so missing
# app font names do not degrade to Courier-like bitmap faces.

SYSTEM_FONT_PACKAGES=(
    adwaita-fonts
    noto-fonts
    noto-fonts-emoji
    ttf-liberation
)

# --------------------------
# Nerd Fonts (terminal / editors / Kitty)
# --------------------------

declare -A NERD_FONTS=(
    ["Meslo"]="ttf-meslo-nerd"
    ["Ubuntu"]="ttf-ubuntu-nerd"
    ["FiraCode"]="ttf-firacode-nerd"
    ["JetBrainsMono"]="ttf-jetbrains-mono-nerd"
    ["Hack"]="ttf-hack-nerd"
)

PACKAGES_TO_INSTALL=()

print_info_message "Checking system UI fonts"
for PACKAGE_NAME in "${SYSTEM_FONT_PACKAGES[@]}"; do
    if pacman -Q "$PACKAGE_NAME" &>/dev/null; then
        print_info_message "Already installed: $PACKAGE_NAME"
    else
        PACKAGES_TO_INSTALL+=("$PACKAGE_NAME")
    fi
done

print_info_message "Checking Nerd Fonts"
for FONT_NAME in "${!NERD_FONTS[@]}"; do
    PACKAGE_NAME="${NERD_FONTS[$FONT_NAME]}"
    if pacman -Q "$PACKAGE_NAME" &>/dev/null; then
        print_info_message "$FONT_NAME Nerd Font already installed"
    else
        PACKAGES_TO_INSTALL+=("$PACKAGE_NAME")
    fi
done

FONTS_UPDATED=false
if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    print_action_message "Installing font package(s): ${PACKAGES_TO_INSTALL[*]}"
    if sudo pacman -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"; then
        print_success_message "Fonts installed successfully"
        FONTS_UPDATED=true
    else
        print_error_message "Some fonts failed to install"
    fi
else
    print_info_message "All shared font packages are already installed"
fi

# --------------------------
# Refresh Font Cache
# --------------------------
# Always refresh on sync/bootstrap so newly linked fontconfig + packages
# are picked up even when pacman had nothing to install.

print_info_message "Refreshing font cache (fc-cache)"
if fc-cache -f; then
    print_success_message "Font cache refreshed"
else
    print_warning_message "fc-cache reported an error"
fi

# Helpful verification for shared stack
if command -v fc-list &>/dev/null; then
    print_info_message "UI: $(fc-list : family | rg -m1 -i '^Adwaita Sans$' || echo 'Adwaita Sans MISSING')"
    print_info_message "Mono: $(fc-list : family | rg -m1 'JetBrainsMono Nerd Font$' || echo 'JetBrainsMono Nerd Font MISSING')"
fi

if [ "$FONTS_UPDATED" = true ]; then
    print_info_message "New fonts installed — log out/in (or restart apps) if title bars still look wrong"
fi

print_tool_setup_complete "Fonts"
