#!/bin/bash

# --------------------------
# Remove Catppuccin Wallpaper Setup
# --------------------------
# This script removes everything installed by the wallpaper section
# of setup-gnome.sh, including:
# - Wallpaper repository
# - Rotation script symlink
# - Autostart entry
# - Custom keybinding (Super+W)
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

print_tool_setup_start "Removing Catppuccin Wallpaper Setup"

# Define paths (same as in setup-gnome.sh)
WALLPAPER_REPO_DIR="$USER_HOME_DIR/.local/share/catppuccin-wallpapers"
WALLPAPER_SCRIPT="$USER_HOME_DIR/.local/bin/rotate-wallpaper.sh"
AUTOSTART_DIR="$USER_HOME_DIR/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/rotate-wallpaper.desktop"
CUSTOM_KEYBINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"

# --------------------------
# Remove Wallpaper Repository
# --------------------------

if [ -d "$WALLPAPER_REPO_DIR" ]; then
    print_info_message "Removing Catppuccin wallpapers repository"
    rm -rf "$WALLPAPER_REPO_DIR"
    print_success_message "Wallpaper repository removed"
else
    print_info_message "Wallpaper repository not found. Skipping."
fi

# --------------------------
# Remove Wallpaper Rotation Script
# --------------------------

if [ -L "$WALLPAPER_SCRIPT" ] || [ -f "$WALLPAPER_SCRIPT" ]; then
    print_info_message "Removing wallpaper rotation script symlink"
    rm -f "$WALLPAPER_SCRIPT"
    print_success_message "Wallpaper rotation script removed"
else
    print_info_message "Wallpaper rotation script not found. Skipping."
fi

# --------------------------
# Remove Autostart Entry
# --------------------------

if [ -f "$AUTOSTART_FILE" ]; then
    print_info_message "Removing autostart entry"
    rm -f "$AUTOSTART_FILE"
    print_success_message "Autostart entry removed"
else
    print_info_message "Autostart entry not found. Skipping."
fi

# --------------------------
# Remove Custom Keybinding (Super+W)
# --------------------------

print_info_message "Removing wallpaper rotation keybinding (Super+W)"

# Get current custom keybindings list
CURRENT_KEYBINDINGS=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)

# Check if custom0 is in the list
if [[ "$CURRENT_KEYBINDINGS" == *"$CUSTOM_KEYBINDING_PATH"* ]]; then
    print_info_message "Removing custom0 keybinding from custom keybindings list"

    # Remove custom0 from the list and update gsettings
    # This filters out the custom0 path and updates the list
    NEW_KEYBINDINGS=$(echo "$CURRENT_KEYBINDINGS" | sed "s|'$CUSTOM_KEYBINDING_PATH', ||g" | sed "s|, '$CUSTOM_KEYBINDING_PATH'||g" | sed "s|'$CUSTOM_KEYBINDING_PATH'|@as []|g")

    # If the result is an empty array representation, set it to empty array
    if [[ "$NEW_KEYBINDINGS" == "@as []" ]]; then
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "[]"
    else
        gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW_KEYBINDINGS"
    fi

    # Reset the individual keybinding settings
    gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KEYBINDING_PATH name 2>/dev/null || true
    gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KEYBINDING_PATH command 2>/dev/null || true
    gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KEYBINDING_PATH binding 2>/dev/null || true

    print_success_message "Keybinding removed"
else
    print_info_message "Custom0 keybinding not found in gsettings. Skipping."
fi

# --------------------------
# Cleanup Complete
# --------------------------

echo ""
print_success_message "Catppuccin wallpaper setup has been completely removed!"
echo ""
print_info_message "Removed items:"
print_info_message "  - Wallpaper repository: $WALLPAPER_REPO_DIR"
print_info_message "  - Rotation script: $WALLPAPER_SCRIPT"
print_info_message "  - Autostart entry: $AUTOSTART_FILE"
print_info_message "  - Keybinding: Super+W (custom0)"
echo ""

print_tool_setup_complete "Removing Catppuccin Wallpaper Setup"
