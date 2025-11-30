#!/bin/bash
#
# Catppuccin Wallpaper Rotator
# Randomly selects a wallpaper from the landscapes folder on each login
#

WALLPAPER_DIR="$HOME/.local/share/catppuccin-wallpapers/landscapes"

# Check if wallpaper directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
    echo "Wallpaper directory not found: $WALLPAPER_DIR"
    exit 1
fi

# Find all image files in the landscapes directory
mapfile -t WALLPAPERS < <(find "$WALLPAPER_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null)

# Check if any wallpapers were found
if [ ${#WALLPAPERS[@]} -eq 0 ]; then
    echo "No wallpapers found in $WALLPAPER_DIR"
    exit 1
fi

# Select a random wallpaper
RANDOM_WALLPAPER="${WALLPAPERS[$RANDOM % ${#WALLPAPERS[@]}]}"

# Set the wallpaper using gsettings
gsettings set org.gnome.desktop.background picture-uri "file://$RANDOM_WALLPAPER"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$RANDOM_WALLPAPER"

echo "Wallpaper set to: $(basename "$RANDOM_WALLPAPER")"
