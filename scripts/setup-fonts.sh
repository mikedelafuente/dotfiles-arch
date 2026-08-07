#!/bin/bash

# --------------------------
# Setup shared UI + Nerd Fonts for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Fonts"

# GNOME 48+ UI fonts + coverage so missing names do not fall back to Courier
SYSTEM_FONT_PACKAGES=(
  adwaita-fonts
  noto-fonts
  noto-fonts-emoji
  ttf-liberation
)

# Terminal / editor Nerd Fonts (Kitty uses JetBrainsMono)
NERD_FONT_PACKAGES=(
  ttf-meslo-nerd
  ttf-ubuntu-nerd
  ttf-firacode-nerd
  ttf-jetbrains-mono-nerd
  ttf-hack-nerd
)

print_info_message "Installing system UI fonts"
ensure_pacman_pkgs "${SYSTEM_FONT_PACKAGES[@]}"

print_info_message "Installing Nerd Fonts"
ensure_pacman_pkgs "${NERD_FONT_PACKAGES[@]}"

# Early refresh; post-link-hooks.sh refreshes again after fonts.conf is linked
refresh_font_cache

if command -v fc-list &>/dev/null; then
  print_info_message "UI: $(fc-list : family | rg -m1 -i '^Adwaita Sans$' || echo 'Adwaita Sans MISSING')"
  print_info_message "Mono: $(fc-list : family | rg -m1 'JetBrainsMono Nerd Font$' || echo 'JetBrainsMono Nerd Font MISSING')"
fi

print_tool_setup_complete "Fonts"
