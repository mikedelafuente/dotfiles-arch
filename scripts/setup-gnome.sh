#!/bin/bash

# --------------------------
# Setup GNOME for Arch Linux with Catppuccin Theme
# --------------------------
# This script configures GNOME with:
# - Dark theme preferences
# - Catppuccin GTK theme (Mocha variant)
# - Catppuccin icon theme (Papirus)
# - GNOME Tweaks and Extensions support
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

print_tool_setup_start "GNOME with Catppuccin Theme"

# --------------------------
# Install GNOME Tools
# --------------------------

print_info_message "Installing GNOME tools and utilities"
yay -S --noconfirm --needed \
    gnome-tweaks \
    gnome-shell-extensions \
    dconf-editor

# --------------------------
# Install Catppuccin GTK Theme
# --------------------------

CATPPUCCIN_GTK_DIR="$USER_HOME_DIR/.themes"
CATPPUCCIN_THEME_NAME="catppuccin-mocha-lavender-standard+default"

if [ -d "$CATPPUCCIN_GTK_DIR/$CATPPUCCIN_THEME_NAME" ]; then
    print_info_message "Catppuccin GTK theme already installed. Skipping."
else
    print_info_message "Installing Catppuccin GTK theme"

    # Create themes directory if it doesn't exist
    mkdir -p "$CATPPUCCIN_GTK_DIR"

    # Install from AUR
    yay -S --noconfirm --needed catppuccin-gtk-theme-mocha

    # Link the theme to user directory for easy access
    if [ -d "/usr/share/themes/$CATPPUCCIN_THEME_NAME" ]; then
        ln -sf "/usr/share/themes/$CATPPUCCIN_THEME_NAME" "$CATPPUCCIN_GTK_DIR/"
        print_info_message "Catppuccin GTK theme installed successfully"
    fi
fi

# --------------------------
# Install Catppuccin Icon Theme (Papirus)
# --------------------------

print_info_message "Installing Papirus icon theme with Catppuccin colors"
yay -S --noconfirm --needed papirus-icon-theme papirus-folders-catppuccin-git

# Apply Catppuccin colors to Papirus folders
if command -v papirus-folders &> /dev/null; then
    print_info_message "Applying Catppuccin Mocha colors to Papirus folders"
    papirus-folders -C cat-mocha-lavender --theme Papirus-Dark
fi

# --------------------------
# Configure GNOME Settings for Dark Theme
# --------------------------

print_info_message "Configuring GNOME for dark theme"

# Set GTK theme to Catppuccin
gsettings set org.gnome.desktop.interface gtk-theme "$CATPPUCCIN_THEME_NAME"

# Set icon theme to Papirus Dark
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"

# Enable dark mode
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Set cursor theme (optional - using Adwaita dark)
gsettings set org.gnome.desktop.interface cursor-theme "Adwaita"

# Set font preferences (optional)
gsettings set org.gnome.desktop.interface font-name "Cantarell 11"
gsettings set org.gnome.desktop.interface document-font-name "Cantarell 11"
gsettings set org.gnome.desktop.interface monospace-font-name "Source Code Pro 10"

# Window manager preferences
gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"

# --------------------------
# Install Catppuccin for GNOME Terminal (Optional)
# --------------------------

print_info_message "Setting up Catppuccin theme for GNOME Terminal"

GNOME_TERMINAL_SCRIPT_URL="https://raw.githubusercontent.com/catppuccin/gnome-terminal/main/install.py"
TEMP_TERMINAL_SCRIPT="/tmp/catppuccin-gnome-terminal-install.py"

if command -v gnome-terminal &> /dev/null; then
    if wget -O "$TEMP_TERMINAL_SCRIPT" "$GNOME_TERMINAL_SCRIPT_URL" 2>/dev/null; then
        print_info_message "Installing Catppuccin theme for GNOME Terminal"
        python3 "$TEMP_TERMINAL_SCRIPT" -f mocha -a lavender
        rm -f "$TEMP_TERMINAL_SCRIPT"
    else
        print_warning_message "Could not download GNOME Terminal theme installer"
        print_info_message "You can manually install from: https://github.com/catppuccin/gnome-terminal"
    fi
else
    print_info_message "GNOME Terminal not found. Skipping terminal theme installation."
fi

# --------------------------
# Setup Catppuccin Wallpapers with Auto-Rotation
# --------------------------

print_info_message "Setting up Catppuccin wallpapers with auto-rotation"

WALLPAPER_REPO_DIR="$USER_HOME_DIR/.local/share/catppuccin-wallpapers"
WALLPAPER_SCRIPT="$USER_HOME_DIR/.local/bin/rotate-wallpaper.sh"
AUTOSTART_DIR="$USER_HOME_DIR/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/rotate-wallpaper.desktop"

# Clone wallpaper repository if it doesn't exist
if [ ! -d "$WALLPAPER_REPO_DIR" ]; then
    print_info_message "Cloning Catppuccin wallpapers repository"
    git clone --depth 1 https://github.com/zhichaoh/catppuccin-wallpapers.git "$WALLPAPER_REPO_DIR"
else
    print_info_message "Catppuccin wallpapers already cloned. Updating..."
    cd "$WALLPAPER_REPO_DIR" && git pull 2>/dev/null || true
fi

# Create wallpaper rotation script
print_info_message "Creating wallpaper rotation script"
mkdir -p "$(dirname "$WALLPAPER_SCRIPT")"

cat > "$WALLPAPER_SCRIPT" << 'WALLPAPER_SCRIPT_EOF'
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
WALLPAPER_SCRIPT_EOF

chmod +x "$WALLPAPER_SCRIPT"
print_info_message "Wallpaper rotation script created at: $WALLPAPER_SCRIPT"

# Create autostart entry for wallpaper rotation
print_info_message "Setting up wallpaper rotation on login"
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_FILE" << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=Rotate Wallpaper
Comment=Randomly rotate Catppuccin wallpaper on login
Exec=/bin/bash -c "$HOME/.local/bin/rotate-wallpaper.sh"
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF

print_info_message "Autostart entry created at: $AUTOSTART_FILE"

# Run the wallpaper rotation script immediately
print_info_message "Setting initial random wallpaper"
bash "$WALLPAPER_SCRIPT"

print_info_message ""
print_info_message "Wallpaper rotation configured successfully!"
print_info_message "  - Wallpapers location: $WALLPAPER_REPO_DIR/landscapes/"
print_info_message "  - Rotation script: $WALLPAPER_SCRIPT"
print_info_message "  - A random wallpaper will be set on each login"
print_info_message ""
print_info_message "To manually change wallpaper, run: $WALLPAPER_SCRIPT"

# --------------------------
# Additional Theme Tweaks
# --------------------------

print_info_message "Applying additional theme tweaks"

# Enable night light (reduces blue light)
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 3700

# Set top bar to show weekday
gsettings set org.gnome.desktop.interface clock-show-weekday true

# Show battery percentage
gsettings set org.gnome.desktop.interface show-battery-percentage true

# --------------------------
# Installation Complete
# --------------------------

echo ""
print_info_message "GNOME configuration completed successfully!"
echo ""
print_info_message "Theme settings applied:"
print_info_message "  - GTK Theme: $CATPPUCCIN_THEME_NAME"
print_info_message "  - Icon Theme: Papirus-Dark (Catppuccin colors)"
print_info_message "  - Color Scheme: Dark"
echo ""
print_info_message "You may need to:"
print_info_message "  1. Log out and log back in for all changes to take effect"
print_info_message "  2. Open GNOME Tweaks to fine-tune appearance settings"
print_info_message "  3. Restart GNOME Shell (Alt+F2, type 'r', press Enter)"
echo ""
print_info_message "To customize further, run: gnome-tweaks"

print_tool_setup_complete "GNOME with Catppuccin Theme"
