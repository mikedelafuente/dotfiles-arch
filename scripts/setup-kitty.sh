#!/bin/bash

# --------------------------
# Setup Kitty Terminal for Arch Linux
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

print_tool_setup_start "Kitty"

# --------------------------
# Install Kitty
# --------------------------

if ! command -v kitty &> /dev/null; then
    print_info_message "Installing Kitty via pacman"
    sudo pacman -S --needed --noconfirm kitty
else
    print_info_message "Kitty is already installed. Skipping installation."
fi

# --------------------------
# Ensure Catppuccin Mocha Theme
# --------------------------
# kitty.conf includes themes/mocha.conf (linked by link-dotfiles.sh).
# Keep a local copy under ~/.config/kitty/themes as a fallback.

KITTY_CONFIG_DIR="$USER_HOME_DIR/.config/kitty"
KITTY_THEME_DIR="$KITTY_CONFIG_DIR/themes"
KITTY_THEME_FILE="$KITTY_THEME_DIR/mocha.conf"

mkdir -p "$KITTY_THEME_DIR"

if [ ! -f "$KITTY_THEME_FILE" ] && [ ! -L "$KITTY_THEME_FILE" ]; then
    print_info_message "Installing Catppuccin Mocha theme for Kitty"
    if wget -q "https://raw.githubusercontent.com/catppuccin/kitty/main/themes/mocha.conf" -O "$KITTY_THEME_FILE"; then
        print_success_message "Catppuccin Mocha theme installed"
    else
        print_error_message "Failed to download Catppuccin Mocha theme"
    fi
else
    print_info_message "Catppuccin Mocha theme already present"
fi

# --------------------------
# Set Default Terminal for All Available Desktop Environments
# --------------------------

kitty_path=$(which kitty)

print_info_message "Kitty path: $kitty_path"

print_info_message "Configuring Kitty as default terminal for all available environments..."

# Configure KDE Plasma (if available)
if command -v kwriteconfig5 &> /dev/null || command -v kwriteconfig6 &> /dev/null; then
    print_info_message "Configuring Kitty as default terminal for KDE"

    if command -v kwriteconfig6 &> /dev/null; then
        KWRITECONFIG="kwriteconfig6"
    else
        KWRITECONFIG="kwriteconfig5"
    fi

    $KWRITECONFIG --file kdeglobals --group General --key TerminalApplication kitty
    $KWRITECONFIG --file kdeglobals --group General --key TerminalService ""

    print_info_message "✓ KDE configured"
else
    print_info_message "KDE configuration tools not found. Skipping KDE setup."
fi

# Configure Gnome (if gsettings is available)
if command -v gsettings &> /dev/null; then
    print_info_message "Configuring Kitty as default terminal for Gnome"

    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''

    print_info_message "✓ Gnome configured"
else
    print_info_message "gsettings not found. Skipping Gnome setup."
fi

print_tool_setup_complete "Kitty"
