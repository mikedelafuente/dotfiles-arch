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
# Machine type (laptop|desktop) drives power policy below
# --------------------------

# Prefer the exported/saved value; fall back to battery detection.
if [[ "${MACHINE_TYPE:-}" != "laptop" && "${MACHINE_TYPE:-}" != "desktop" ]]; then
    load_bootstrap_config || true
fi
if machine_is_laptop; then
    MACHINE_TYPE="laptop"
else
    MACHINE_TYPE="desktop"
fi
print_info_message "Machine type: $MACHINE_TYPE"

# --------------------------
# Install GNOME Tools
# --------------------------

print_info_message "Installing GNOME tools and utilities"
ensure_pacman_pkgs \
    gnome-tweaks \
    gnome-shell-extensions \
    dconf-editor

# --------------------------
# Change how sound power works in order to stop popping
# --------------------------

# Keep audio power saving only on laptops; desktops pop when the codec sleeps.
if [ "$MACHINE_TYPE" = "laptop" ]; then
    print_info_message "Laptop - keeping audio power saving enabled for better battery life"
    print_info_message "If you experience audio popping, you can manually disable with:"
    print_info_message "  echo 'options snd_hda_intel power_save=0' | sudo tee /etc/modprobe.d/audio_disable_powersave.conf"
else
    print_info_message "Desktop - disabling audio power saving to prevent popping sounds"
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
    ensure_yay_pkgs catppuccin-gtk-theme-mocha

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
ensure_pacman_pkgs papirus-icon-theme
ensure_yay_pkgs papirus-folders-catppuccin-git

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

# Set shared fonts (installed by setup-fonts.sh; GNOME 48+ uses Adwaita)
# Cantarell / Source Code Pro are often missing and fall back to Courier-like faces.
gsettings set org.gnome.desktop.interface font-name "Adwaita Sans 11"
gsettings set org.gnome.desktop.interface document-font-name "Adwaita Sans 11"
gsettings set org.gnome.desktop.interface monospace-font-name "JetBrainsMono Nerd Font 10"
gsettings set org.gnome.desktop.wm.preferences titlebar-uses-system-font false
gsettings set org.gnome.desktop.wm.preferences titlebar-font "Adwaita Sans Bold 11"

# Window manager preferences
gsettings set org.gnome.desktop.wm.preferences button-layout "appmenu:minimize,maximize,close"

# --------------------------
# GNOME Terminal theme
# --------------------------
# Kitty is the default terminal; skip remote GNOME Terminal theme installers.

print_info_message "Skipping GNOME Terminal Catppuccin theme (Kitty is the default terminal)"

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

# Touchpad: never use tap-to-click (physical click only)
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click false

# Default browser + Super+B launcher
# Prefer Chrome when the work profile is selected (even alongside personal/devcontainer).
if ! load_bootstrap_config; then
  SETUP_PROFILES="${SETUP_PROFILES:-}"
  SETUP_PROFILE="${SETUP_PROFILE:-}"
fi

DEFAULT_BROWSER_DESKTOP="firefox.desktop"
BROWSER_COMMAND="firefox"
if has_setup_profile work || [[ "${SETUP_PROFILE:-}" == "work" ]]; then
  DEFAULT_BROWSER_DESKTOP="google-chrome.desktop"
  if command -v google-chrome-stable &>/dev/null; then
    BROWSER_COMMAND="google-chrome-stable"
  else
    BROWSER_COMMAND="google-chrome"
  fi
elif has_setup_profile personal || [[ "${SETUP_PROFILE:-}" == "personal" ]]; then
  DEFAULT_BROWSER_DESKTOP="firefox.desktop"
  BROWSER_COMMAND="firefox"
else
  # Fallback when no browser profile: prefer whatever is installed
  if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
    DEFAULT_BROWSER_DESKTOP="google-chrome.desktop"
    BROWSER_COMMAND="$(command -v google-chrome-stable 2>/dev/null || command -v google-chrome)"
  fi
fi

print_info_message "Setting default browser to $DEFAULT_BROWSER_DESKTOP ($BROWSER_COMMAND)"
xdg-settings set default-web-browser "$DEFAULT_BROWSER_DESKTOP" 2>/dev/null \
  || print_warning_message "Could not set default browser via xdg-settings"

# --------------------------
# Configure Power Management for Media Playback
# --------------------------

# Configure power settings to ensure media playback inhibits sleep
print_info_message "Configuring power management for media playback"

# GNOME automatically detects media playback via MPRIS and inhibits both sleep AND screen blanking
# These settings allow sleep/screen blank when truly idle, but respect inhibitors (like media playback)
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0  # Never sleep on AC power when idle
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 1800  # Sleep after 30min on battery

# Screen blanking (MPRIS-aware players will prevent this during playback)
# Set to 20 minutes so screen blanks when you walk away, but videos keep screen on
gsettings set org.gnome.desktop.session idle-delay 1200  # Blank screen after 20 minutes of inactivity (but NOT during video playback)

# --------------------------
# Power profile + lid behavior (MACHINE_TYPE driven)
# --------------------------

print_info_message "Applying $MACHINE_TYPE power policy"
ensure_pacman_pkgs power-profiles-daemon

if systemctl list-unit-files power-profiles-daemon.service 2>/dev/null | grep -q power-profiles-daemon; then
    sudo systemctl enable --now power-profiles-daemon.service \
      || print_warning_message "Could not enable power-profiles-daemon.service"
fi

if command -v powerprofilesctl &>/dev/null; then
    if [ "$MACHINE_TYPE" = "laptop" ]; then
        DESIRED_POWER_PROFILE="balanced"
    else
        DESIRED_POWER_PROFILE="performance"
    fi
    if powerprofilesctl list 2>/dev/null | grep -q "$DESIRED_POWER_PROFILE"; then
        powerprofilesctl set "$DESIRED_POWER_PROFILE" \
          || print_warning_message "Could not set power profile to $DESIRED_POWER_PROFILE"
        print_info_message "Power profile: $DESIRED_POWER_PROFILE"
    else
        print_warning_message "Power profile '$DESIRED_POWER_PROFILE' unavailable on this hardware"
    fi
fi

# Lid handling lives in systemd-logind, not gsettings.
LOGIND_LID_DROPIN="/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf"
if [ "$MACHINE_TYPE" = "laptop" ]; then
    LID_ACTION="suspend"
else
    LID_ACTION="ignore"
fi
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee "$LOGIND_LID_DROPIN" >/dev/null <<EOF
# Managed by dotfiles-arch (setup-gnome.sh) — MACHINE_TYPE=$MACHINE_TYPE
[Login]
HandleLidSwitch=$LID_ACTION
HandleLidSwitchExternalPower=$LID_ACTION
HandleLidSwitchDocked=ignore
EOF
print_info_message "Lid switch: $LID_ACTION (takes effect after re-login or reboot)"

print_info_message ""
print_info_message "Sleep and screen blanking prevention configured!"
print_info_message "  - GNOME automatically detects video playback via MPRIS"
print_info_message "  - During video playback: screen stays on, system doesn't sleep"
print_info_message "  - When idle (no video): screen blanks after 20min, system sleeps per power settings"
print_info_message "  - Supported players: Firefox, Chrome, VLC, mpv, celluloid, and most modern media apps"
print_info_message ""

# --------------------------
# Install and Configure Pop Shell for Tiling Window Management
# --------------------------

print_info_message "Installing Pop Shell for tiling window management"
ensure_yay_pkgs gnome-shell-extension-pop-shell-git

# Skip GNOME Activities overview at login (land on workspace 1 / desktop)
print_info_message "Installing No Overview extension (skip workspace picker at login)"
ensure_yay_pkgs gnome-shell-extension-no-overview

# AppIndicators for tray icons (Slack, Discord, Spotify, etc.)
print_info_message "Installing AppIndicator extension"
sudo pacman -S --needed --noconfirm gnome-shell-extension-appindicator

# GPaste clipboard history (GNOME-native)
print_info_message "Installing GPaste clipboard manager"
sudo pacman -S --needed --noconfirm gpaste

# Ensure extension UUIDs are present in org.gnome.shell enabled-extensions.
# gnome-extensions enable alone often no-ops outside an interactive session.
ensure_gnome_extension_enabled() {
  local uuid="$1"
  gnome-extensions enable "$uuid" 2>/dev/null || true
  python3 - "$uuid" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True
).strip()
if raw.startswith("@as"):
    raw = raw.split(None, 1)[1]
exts = list(ast.literal_eval(raw))
if uuid not in exts:
    exts.append(uuid)
    out = "[" + ", ".join(f"'{e}'" for e in exts) + "]"
    subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", out])
    print(f"added {uuid}")
else:
    print(f"already enabled: {uuid}")
PY
}

print_info_message "Enabling GNOME Shell extensions (Pop Shell, No Overview, AppIndicator, GPaste)"
# Pop Shell AUR builds often lag GNOME major versions; allow loading anyway.
gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
ensure_gnome_extension_enabled "pop-shell@system76.com"
ensure_gnome_extension_enabled "no-overview@fthx"
ensure_gnome_extension_enabled "appindicatorsupport@rgcjonas.gmail.com"
ensure_gnome_extension_enabled "GPaste@gnome-shell-extensions.gnome.org"
print_info_message "enabled-extensions=$(gsettings get org.gnome.shell enabled-extensions)"
print_warning_message "New system extensions need a log out/in before GNOME Shell discovers them."

# Start GPaste daemon and tune history
systemctl --user enable --now org.gnome.GPaste.service 2>/dev/null \
  || gpaste-client daemon-reexec 2>/dev/null \
  || print_warning_message "Start GPaste later with: systemctl --user enable --now org.gnome.GPaste.service"
gsettings set org.gnome.GPaste images-support true 2>/dev/null || true
gsettings set org.gnome.GPaste max-history-size 100 2>/dev/null || true
gsettings set org.gnome.GPaste max-displayed-history-size 20 2>/dev/null || true
# Extension-owned accelerator left empty — Super+V is a custom media-keys
# binding to `gpaste-client show-history` so it works even when the extension
# shortcut handler has not loaded yet.
gsettings set org.gnome.GPaste show-history '' 2>/dev/null || true

# Configure Pop Shell settings
print_info_message "Configuring Pop Shell tiling behavior"

# Enable tiling by default
gsettings set org.gnome.shell.extensions.pop-shell tile-by-default true

# Explicitly bind Super+Y (toggle auto-tiling for the workspace)
gsettings set org.gnome.shell.extensions.pop-shell toggle-tiling "['<Super>y']"
# Float / unfloat focused window
gsettings set org.gnome.shell.extensions.pop-shell toggle-floating "['<Super>g']"

# Configure gaps (optional - adjust to your preference)
gsettings set org.gnome.shell.extensions.pop-shell gap-inner 4
gsettings set org.gnome.shell.extensions.pop-shell gap-outer 4

# Configure hints (turn off or on based on preference)
gsettings set org.gnome.shell.extensions.pop-shell hint-color-rgba 'rgba(147, 153, 178, 0.5)'
gsettings set org.gnome.shell.extensions.pop-shell active-hint true

# Clear Pop Shell's Super+Return keybinding (conflicts with terminal launcher).
# Rebind tile adjustment mode to Super+Escape instead.
print_info_message "Clearing Pop Shell keybindings that conflict with our shortcuts"
gsettings set org.gnome.shell.extensions.pop-shell tile-enter "['<Super>Escape']"

# Super+Ctrl+Left/Right: snap/tile on the current monitor (Mutter defaults)
gsettings set org.gnome.mutter.keybindings toggle-tiled-left "['<Primary><Super>Left']"
gsettings set org.gnome.mutter.keybindings toggle-tiled-right "['<Primary><Super>Right']"

# Super+Ctrl+Up/Down must NOT switch workspaces (GNOME default steals these chords)
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down "[]"

# Super+Ctrl+Up/Down: move window between monitors.
# Monitors are usually arranged left/right, so Up/Down map to left/right hops
# (geometric Up/Down only works when displays are stacked vertically).
print_info_message "Configuring Super+Ctrl+Up/Down to move windows between monitors"
gsettings set org.gnome.shell.extensions.pop-shell pop-monitor-left "['<Primary><Super>Up']"
gsettings set org.gnome.shell.extensions.pop-shell pop-monitor-right "['<Primary><Super>Down']"
gsettings set org.gnome.shell.extensions.pop-shell pop-monitor-up "[]"
gsettings set org.gnome.shell.extensions.pop-shell pop-monitor-down "[]"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-left "['<Primary><Super>Up']"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-right "['<Primary><Super>Down']"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-up "[]"
gsettings set org.gnome.desktop.wm.keybindings move-to-monitor-down "[]"

# --------------------------
# Clear Conflicting Default Keybindings
# --------------------------

print_info_message "Clearing GNOME default keybindings that conflict with our workflow"

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

# Super+E opens the file explorer via GNOME's built-in "Home folder" binding.
# Clear Email first — it commonly steals Super+E (empty string disables the shortcut).
gsettings set org.gnome.settings-daemon.plugins.media-keys email "['']"
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"

# --------------------------
# Configure workspace keybindings
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

# Close window with Super+Q
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
# Configure application launch keybindings
# --------------------------

print_info_message "Configuring tiling / Pop Shell application launcher shortcuts"

# Super+Return for terminal (using kitty if available, fallback to gnome-terminal)
CUSTOM_KB_TERMINAL="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL name 'Launch Terminal'
if command -v kitty &> /dev/null; then
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL command 'kitty'
else
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL command 'gnome-terminal'
fi
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_TERMINAL binding '<Super>Return'

# Super+B for browser (Chrome on work, Firefox on personal)
CUSTOM_KB_BROWSER="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom3/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER name 'Launch Browser'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER command "$BROWSER_COMMAND"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_BROWSER binding '<Super>b'

# Super+V clipboard history via gpaste-client (works even if the shell extension
# shortcut handler has not loaded yet; safe alongside GPaste show-history)
CUSTOM_KB_CLIPBOARD="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom4/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_CLIPBOARD name 'Clipboard History'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_CLIPBOARD command 'gpaste-client show-history'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_CLIPBOARD binding '<Super>v'

# Super+. for the emoji picker
ensure_pacman_pkgs gnome-characters
CUSTOM_KB_EMOJI="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI name 'Emoji Picker'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI command 'gnome-characters'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI binding '<Super>period'

# Super+Shift+Return for a Herdr session (Super+Return stays a plain terminal)
CUSTOM_KB_HERDR="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_HERDR name 'Launch Herdr'
if command -v kitty &> /dev/null; then
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_HERDR command 'kitty herdr'
else
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_HERDR command 'gnome-terminal -- herdr'
fi
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_HERDR binding '<Super><Shift>Return'

# Update the custom keybindings list (no empty custom0; Super+E uses built-in Home)
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
  "['$CUSTOM_KB_TERMINAL', '$CUSTOM_KB_EMOJI', '$CUSTOM_KB_BROWSER', '$CUSTOM_KB_CLIPBOARD', '$CUSTOM_KB_HERDR']"

# Screenshot UI (region/window/screen picker, includes copy to clipboard)
gsettings set org.gnome.shell.keybindings show-screenshot-ui "['<Super><Shift>s', 'Print']"

# Minimize — Super+Shift+N (never Super+H: Pop Shell uses it for focus-left)
gsettings set org.gnome.desktop.wm.keybindings minimize "['<Super><Shift>n']"

# Configure Super+Space for app launcher (GNOME overview with app grid)
gsettings set org.gnome.shell.keybindings toggle-application-view "['<Super>space']"

# Disable default Super key behavior (opening activities overview on single press)
gsettings set org.gnome.mutter overlay-key ''

# Disable hot corners (prevents Activities overview from triggering on hover in top-left corner)
gsettings set org.gnome.desktop.interface enable-hot-corners false

# Clear other default overlay shortcuts that might conflict
gsettings set org.gnome.shell.keybindings toggle-overview "[]"

print_info_message ""
print_success_message "Window manager keybindings configured!"
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
print_info_message "  - Minimize window: Super+Shift+N"
print_info_message "  - Tile left/right (this monitor): Super+Ctrl+Left/Right"
print_info_message "  - Move window to other monitor: Super+Ctrl+Up/Down"
print_info_message "  - Pop Shell toggle auto-tiling: Super+Y"
print_info_message "  - Pop Shell float focused window: Super+G"
print_info_message "  - Pop Shell tile adjustment mode: Super+Escape"
print_info_message "  - Switch windows: Alt+Tab"
print_info_message ""
print_info_message "Application Launchers:"
print_info_message "  - App Launcher: Super+Space"
print_info_message "  - Terminal: Super+Return"
print_info_message "  - Herdr session: Super+Shift+Return"
print_info_message "  - File Explorer: Super+E"
print_info_message "  - Browser: Super+B"
print_info_message "  - Clipboard history (GPaste): Super+V"
print_info_message "  - Emoji picker: Super+."
print_info_message "  - Screenshot UI: Super+Shift+S (or Print)"
print_info_message ""
print_warning_message "Log out and back in so GNOME reloads extensions (GPaste, AppIndicator, Pop Shell)."
print_warning_message "Until then Super+V / Super+Y / tray icons may not work."

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
