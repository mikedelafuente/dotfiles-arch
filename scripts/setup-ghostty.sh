#!/bin/bash

# --------------------------
# Setup Ghostty Terminal for Arch Linux
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

print_tool_setup_start "Ghostty"

# --------------------------
# Install Ghostty
# --------------------------

# Install Ghostty using yay (AUR package)
if ! command -v ghostty &> /dev/null; then
    print_info_message "Installing Ghostty via yay (AUR)"
    yay -S --needed --noconfirm ghostty
else
    print_info_message "Ghostty is already installed. Skipping installation."
fi

# --------------------------
# Install Catppuccin Theme for Ghostty
# --------------------------

GHOSTTY_THEMES_DIR="$USER_HOME_DIR/.config/ghostty/themes"
CATPPUCCIN_THEME_FILE="$GHOSTTY_THEMES_DIR/catppuccin-mocha"

if [ ! -f "$CATPPUCCIN_THEME_FILE" ]; then
    print_info_message "Installing Catppuccin theme for Ghostty"

    mkdir -p "$GHOSTTY_THEMES_DIR"

    # Download Catppuccin Mocha theme
    if wget -q "https://raw.githubusercontent.com/catppuccin/ghostty/main/themes/mocha" -O "$CATPPUCCIN_THEME_FILE"; then
        print_info_message "Catppuccin Mocha theme installed successfully"
    else
        print_error_message "Failed to download Catppuccin theme"
    fi
else
    print_info_message "Catppuccin theme already installed. Skipping."
fi

# --------------------------
# Set Default Terminal for All Available Desktop Environments
# --------------------------

# Get the path to Ghostty
ghostty_path=$(which ghostty)

print_info_message "Ghostty path: $ghostty_path"

# Configure for all available desktop environments (user switches between them)
print_info_message "Configuring Ghostty as default terminal for all available environments..."

# Configure KDE Plasma (if available)
if command -v kwriteconfig5 &> /dev/null || command -v kwriteconfig6 &> /dev/null; then
    print_info_message "Configuring Ghostty as default terminal for KDE"

    # Determine which version of kwriteconfig is available (KDE 5 or KDE 6)
    if command -v kwriteconfig6 &> /dev/null; then
        KWRITECONFIG="kwriteconfig6"
    else
        KWRITECONFIG="kwriteconfig5"
    fi

    # Set Ghostty as the default terminal in KDE settings
    $KWRITECONFIG --file kdeglobals --group General --key TerminalApplication ghostty
    $KWRITECONFIG --file kdeglobals --group General --key TerminalService ""

    print_info_message "✓ KDE configured"
else
    print_info_message "KDE configuration tools not found. Skipping KDE setup."
fi

# Configure Gnome (if gsettings is available)
if command -v gsettings &> /dev/null; then
    print_info_message "Configuring Ghostty as default terminal for Gnome"

    # Set Ghostty as the default terminal in Gnome settings
    # This will work even if not currently in a Gnome session
    gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''

    print_info_message "✓ Gnome configured"
else
    print_info_message "gsettings not found. Skipping Gnome setup."
fi

# Hyprland configuration reminder
print_info_message ""
print_info_message "For Hyprland, make sure your hyprland.conf includes:"
print_info_message "  bind = \$mainMod, Return, exec, ghostty"
print_info_message "  or"
print_info_message "  \$terminal = ghostty"
print_info_message "  bind = \$mainMod, Return, exec, \$terminal"

print_tool_setup_complete "Ghostty"
