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
# Change how sound power works in order to stop popping
# --------------------------

# Only disable audio power saving on desktops (systems without batteries)
if [ -d /sys/class/power_supply/BAT* ] 2>/dev/null || [ -d /sys/class/power_supply/battery ] 2>/dev/null; then
    print_info_message "Battery detected - keeping audio power saving enabled for better battery life"
    print_info_message "If you experience audio popping, you can manually disable with:"
    print_info_message "  echo 'options snd_hda_intel power_save=0' | sudo tee /etc/modprobe.d/audio_disable_powersave.conf"
else
    print_info_message "No battery detected (desktop system) - disabling audio power saving to prevent popping sounds"
    echo "options snd_hda_intel power_save=0" | sudo tee /etc/modprobe.d/audio_disable_powersave.conf > /dev/null
fi

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

# Set Firefox as default browser
print_info_message "Setting Firefox as default browser"
xdg-settings set default-web-browser firefox.desktop

CUSTOM_KEYBINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"

# --------------------------
# Install Caffeine for Preventing Sleep During Media Playback
# --------------------------

print_info_message "Installing Caffeine to prevent sleep during active use"

# Install caffeine-ng (works across desktop environments and has better GNOME integration)
yay -S --noconfirm --needed caffeine-ng

# Configure power settings to ensure media playback inhibits sleep
print_info_message "Configuring power management for media playback"

# GNOME automatically detects media playback via MPRIS and inhibits both sleep AND screen blanking
# These settings allow sleep/screen blank when truly idle, but respect inhibitors (like media playback)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0  # Never sleep on AC power when idle
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 1800  # Sleep after 30min on battery

# Screen blanking (MPRIS-aware players will prevent this during playback)
# Set to 20 minutes so screen blanks when you walk away, but videos keep screen on
gsettings set org.gnome.desktop.session idle-delay 1200  # Blank screen after 20 minutes of inactivity (but NOT during video playback)

print_info_message ""
print_info_message "Sleep and screen blanking prevention configured!"
print_info_message "  - GNOME automatically detects video playback via MPRIS"
print_info_message "  - During video playback: screen stays on, system doesn't sleep"
print_info_message "  - When idle (no video): screen blanks after 20min, system sleeps per power settings"
print_info_message "  - Supported players: Firefox, Chrome, VLC, mpv, celluloid, and most modern media apps"
print_info_message "  - Caffeine-ng provides a system tray icon for manual override when needed"
print_info_message ""

# --------------------------
# Install and Configure Pop Shell for Tiling Window Management
# --------------------------

print_info_message "Installing Pop Shell for tiling window management"
yay -S --noconfirm --needed gnome-shell-extension-pop-shell-git

# Enable Pop Shell extension
print_info_message "Enabling Pop Shell extension"
gnome-extensions enable pop-shell@system76.com 2>/dev/null || print_warning_message "Pop Shell will be enabled after GNOME Shell restart"

# Configure Pop Shell settings
print_info_message "Configuring Pop Shell tiling behavior"

# Enable tiling by default
gsettings set org.gnome.shell.extensions.pop-shell tile-by-default true

# Configure gaps (optional - adjust to your preference)
gsettings set org.gnome.shell.extensions.pop-shell gap-inner 4
gsettings set org.gnome.shell.extensions.pop-shell gap-outer 4

# Configure hints (turn off or on based on preference)
gsettings set org.gnome.shell.extensions.pop-shell hint-color-rgba 'rgba(147, 153, 178, 0.5)'
gsettings set org.gnome.shell.extensions.pop-shell active-hint true

# Clear Pop Shell's Super+Return keybinding (conflicts with terminal launcher)
print_info_message "Clearing Pop Shell keybindings that conflict with Hyprland-style shortcuts"
gsettings set org.gnome.shell.extensions.pop-shell tile-enter "[]"

# --------------------------
# Clear Conflicting Default Keybindings
# --------------------------

print_info_message "Clearing GNOME default keybindings that conflict with Hyprland-style workflow"

# Disable Super+number app launcher keybindings (these launch favorite apps by default)
gsettings set org.gnome.shell.keybindings switch-to-application-1 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-2 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-3 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-4 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-5 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-6 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-7 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-8 "[]"
gsettings set org.gnome.shell.keybindings switch-to-application-9 "[]"

# Disable other potentially conflicting keybindings
gsettings set org.gnome.shell.keybindings focus-active-notification "[]"
gsettings set org.gnome.shell.keybindings toggle-message-tray "[]"

# Clear Super+Space from input source switching (this is usually the default)
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "[]"

# --------------------------
# Configure Workspace Keybindings (Hyprland-like)
# --------------------------

print_info_message "Configuring workspace switching keybindings (Super+1-9)"

# Switch to workspace 1-9 with Super+[number]
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-1 "['<Super>1']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-2 "['<Super>2']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-3 "['<Super>3']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-4 "['<Super>4']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-5 "['<Super>5']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-6 "['<Super>6']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-7 "['<Super>7']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-8 "['<Super>8']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-9 "['<Super>9']"

print_info_message "Configuring window movement keybindings (Super+Shift+1-9)"

# Move window to workspace 1-9 with Super+Shift+[number]
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-1 "['<Super><Shift>1']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-2 "['<Super><Shift>2']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-3 "['<Super><Shift>3']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-4 "['<Super><Shift>4']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-5 "['<Super><Shift>5']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-6 "['<Super><Shift>6']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-7 "['<Super><Shift>7']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-8 "['<Super><Shift>8']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-9 "['<Super><Shift>9']"

# --------------------------
# Configure Additional Window Management Keybindings
# --------------------------

print_info_message "Configuring additional window management shortcuts"

# Enable static workspaces (disable dynamic workspaces)
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 9

# Close window with Super+Q (Hyprland-like)
gsettings set org.gnome.desktop.wm.keybindings close "['<Super>q', '<Alt>F4']"

# Toggle fullscreen with Super+F
gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['<Super>f']"

# Maximize/unmaximize toggle
gsettings set org.gnome.desktop.wm.keybindings toggle-maximized "['<Super>m']"

# Window focus switching
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"

# Additional navigation left/right through workspaces
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-left "['<Super><Alt>Left']"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-right "['<Super><Alt>Right']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-left "['<Super><Shift><Alt>Left']"
gsettings set org.gnome.desktop.wm.keybindings move-to-workspace-right "['<Super><Shift><Alt>Right']"

# --------------------------
# Configure Application Launch Keybindings (Hyprland-like)
# --------------------------

print_info_message "Configuring Hyprland-style application launcher shortcuts"

# Super+Return for terminal (using kitty if available, fallback to gnome-terminal)
CUSTOM_KB_TERMINAL="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL name 'Launch Terminal'
if command -v kitty &> /dev/null; then
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL command 'kitty'
else
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL command 'gnome-terminal'
fi
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL binding '<Super>Return'

# Super+E for file manager
CUSTOM_KB_FILES="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_FILES name 'Launch File Manager'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_FILES command 'nautilus'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_FILES binding '<Super>e'

# Super+B for browser (Firefox)
CUSTOM_KB_BROWSER="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER name 'Launch Browser'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER command 'firefox'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER binding '<Super>b'

# Update the custom keybindings list to include all custom shortcuts
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$CUSTOM_KEYBINDING_PATH', '$CUSTOM_KB_TERMINAL', '$CUSTOM_KB_FILES', '$CUSTOM_KB_BROWSER']"

# Configure Super+Space for app launcher (GNOME overview with app grid)
gsettings set org.gnome.shell.keybindings toggle-application-view "['<Super>space']"

# Disable default Super key behavior (opening activities overview on single press)
gsettings set org.gnome.mutter overlay-key ''

# Disable hot corners (prevents Activities overview from triggering on hover in top-left corner)
gsettings set org.gnome.desktop.interface enable-hot-corners false

# Clear other default overlay shortcuts that might conflict
gsettings set org.gnome.shell.keybindings toggle-overview "[]"

print_info_message ""
print_success_message "Hyprland-style keybindings configured!"
print_info_message ""
print_info_message "Workspace Management:"
print_info_message "  - Switch to workspace: Super+1 through Super+9"
print_info_message "  - Move window to workspace: Super+Shift+1 through Super+Shift+9"
print_info_message "  - Switch workspace left/right: Super+Alt+Left/Right"
print_info_message "  - Move window left/right: Super+Shift+Alt+Left/Right"
print_info_message ""
print_info_message "Window Management:"
print_info_message "  - Close window: Super+Q"
print_info_message "  - Toggle fullscreen: Super+F"
print_info_message "  - Toggle maximize: Super+M"
print_info_message "  - Pop Shell toggle tiling: Super+Y"
print_info_message "  - Switch windows: Alt+Tab"
print_info_message ""
print_info_message "Application Launchers:"
print_info_message "  - App Launcher: Super+Space"
print_info_message "  - Terminal: Super+Return"
print_info_message "  - File Manager: Super+E"
print_info_message "  - Browser (Firefox): Super+B"

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
