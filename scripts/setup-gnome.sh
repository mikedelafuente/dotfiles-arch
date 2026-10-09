#!/bin/bash

# --------------------------
# Setup GNOME for Arch Linux / Ubuntu 26.04 with Catppuccin Theme
# --------------------------
# This script configures GNOME with:
# - Dark theme preferences
# - Catppuccin GTK theme (Mocha variant)
# - Catppuccin icon theme (Papirus)
# - Dash to Panel (always-visible top app bar)
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

if ! native_package_installed gnome-shell; then
    print_info_message "GNOME is not installed — skipping desktop setup"
    exit 0
fi
[[ "$EUID" != 0 && -z "${SUDO_USER:-}" ]] || {
    print_error_message "Run GNOME setup as the workstation user, without sudo"
    exit 1
}
GNOME_SHELL_VERSION="$(gnome-shell --version | sed -nE 's/^GNOME Shell ([0-9]+(\.[0-9]+)*).*$/\1/p')"
[[ -n "$GNOME_SHELL_VERSION" ]] || { print_error_message "Cannot determine installed GNOME Shell version"; exit 1; }
GNOME_POLICIES_DEFERRED=false

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
GNOME_MACHINE_TYPE="$MACHINE_TYPE"
print_info_message "Machine type: $MACHINE_TYPE"

# --------------------------
# Install GNOME Tools
# --------------------------

print_info_message "Installing GNOME tools and utilities"
ensure_native_pkgs \
    gnome-tweaks \
    gnome-shell-extensions \
    dconf-editor \
    gnome-characters
if [[ "$WORKSTATION_DISTRO" == arch ]]; then ensure_native_pkgs python; else ensure_native_pkgs python3; fi
ensure_gnome_extensions "$GNOME_SHELL_VERSION" || exit 1

# --------------------------
# Change how sound power works in order to stop popping
# --------------------------

# Keep audio power saving only on laptops; desktops pop when the codec sleeps.
if [ "$MACHINE_TYPE" = "laptop" ]; then
    AUDIO_POWER_SAVE=1
else
    AUDIO_POWER_SAVE=0
fi
gnome_write_policy /etc/modprobe.d/audio_disable_powersave.conf audio \
    '^[[:space:]]*options[[:space:]]+snd_hda_intel[[:space:]].*power_save' \
    "# Managed by dotfiles-arch (setup-gnome.sh) — MACHINE_TYPE=$MACHINE_TYPE
options snd_hda_intel power_save=$AUDIO_POWER_SAVE" /etc/modprobe.d/*.conf /run/modprobe.d/*.conf

# --------------------------
# Install Catppuccin GTK Theme
# --------------------------

CATPPUCCIN_THEME_NAME="catppuccin-mocha-lavender-standard+default"
ensure_gnome_appearance || exit 1

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
MACHINE_TYPE="$GNOME_MACHINE_TYPE"

CHROME_COMMAND=''
if command -v google-chrome-stable &>/dev/null; then CHROME_COMMAND=google-chrome-stable
elif command -v google-chrome &>/dev/null; then CHROME_COMMAND=google-chrome; fi
FIREFOX_DESKTOP=''
if ! has_setup_profile work && { has_setup_profile personal || [[ -z "$CHROME_COMMAND" ]]; }; then
    FIREFOX_DESKTOP="$(personal_app_desktop firefox)" || {
        print_error_message "Selected Firefox source/desktop unavailable or conflicting; preserved"
        exit 1
    }
fi
BROWSER_SELECTION="$(personal_browser_selection "${SETUP_PROFILES:-${SETUP_PROFILE:-}}" "$CHROME_COMMAND" "$FIREFOX_DESKTOP")" || {
    print_error_message "Selected browser launcher is unavailable; GNOME browser shortcut cannot be configured"
    exit 1
}
read -r DEFAULT_BROWSER_DESKTOP BROWSER_COMMAND <<<"$BROWSER_SELECTION"

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
ALTERNATE_POWER_MANAGER=false
if native_package_installed tuned-ppd || native_package_installed tuned || native_package_installed tlp \
    || native_package_installed system76-power; then ALTERNATE_POWER_MANAGER=true; fi
POWER_DAEMON_EXISTED=false
native_package_installed power-profiles-daemon && POWER_DAEMON_EXISTED=true
POWER_LOAD_STATE="$(systemctl show power-profiles-daemon.service -p LoadState --value 2>/dev/null || true)"
POWER_ACTIVE_STATE="$(systemctl show power-profiles-daemon.service -p ActiveState --value 2>/dev/null || true)"
POWER_ACTION="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" power "$ALTERNATE_POWER_MANAGER" \
    "$POWER_DAEMON_EXISTED" "$POWER_LOAD_STATE" "$POWER_ACTIVE_STATE")"
case "$POWER_ACTION" in
    defer)
        GNOME_POLICIES_DEFERRED=true
        print_warning_message "Preserved alternate/masked/inactive power manager; power profile policy deferred"
        ;;
    unavailable)
        print_error_message "Installed power-profiles-daemon has no usable service; power policy cannot be applied"
        exit 1
        ;;
    install|apply)
        if [[ "$POWER_ACTION" == install ]]; then
            ensure_native_pkgs power-profiles-daemon
            gnome_service_loaded system power-profiles-daemon.service || {
                print_error_message "Required power-profiles-daemon.service unavailable"; exit 1;
            }
            sudo systemctl enable --now power-profiles-daemon.service
        fi
        if [ "$MACHINE_TYPE" = "laptop" ]; then
            DESIRED_POWER_PROFILE="balanced"
        else
            DESIRED_POWER_PROFILE="performance"
        fi
        AVAILABLE_POWER_PROFILES="$(powerprofilesctl list)"
        if grep -Eq "^[[:space:]*]*$DESIRED_POWER_PROFILE:" <<<"$AVAILABLE_POWER_PROFILES"; then
            if powerprofilesctl set "$DESIRED_POWER_PROFILE"; then
                print_info_message "Power profile: $DESIRED_POWER_PROFILE"
            else
                print_error_message "Could not apply $DESIRED_POWER_PROFILE; existing power profile retained"
                exit 1
            fi
        else
            print_warning_message "Power profile '$DESIRED_POWER_PROFILE' unavailable on this hardware"
        fi
        ;;
esac

# Lid handling lives in systemd-logind, not gsettings.
# Laptop: suspend on battery lid-close; ignore on AC / when docked so a closed-lid
# KVM desk setup stays awake. Desktop: always ignore.
LOGIND_LID_DROPIN="/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf"
if [ "$MACHINE_TYPE" = "laptop" ]; then
    LID_ON_BATTERY="suspend"
    LID_ON_AC="ignore"
else
    LID_ON_BATTERY="ignore"
    LID_ON_AC="ignore"
fi
gnome_write_policy "$LOGIND_LID_DROPIN" lid '^[[:space:]]*HandleLidSwitch(ExternalPower|Docked)?[[:space:]]*=' \
"# Managed by dotfiles-arch (setup-gnome.sh) — MACHINE_TYPE=$MACHINE_TYPE
[Login]
HandleLidSwitch=$LID_ON_BATTERY
HandleLidSwitchExternalPower=$LID_ON_AC
HandleLidSwitchDocked=ignore" /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf /run/systemd/logind.conf.d/*.conf
print_info_message "Requested lid switch: battery=$LID_ON_BATTERY AC=$LID_ON_AC docked=ignore (reboot to apply owned policy)"

# USB HID / hub wake — closed-lid KVM keyboards and mice can resume from suspend.
# Always written (harmless on desktop); laptop is the primary use case.
USB_WAKE_UDEV="/etc/udev/rules.d/90-dotfiles-arch-usb-wakeup.rules"
gnome_write_policy "$USB_WAKE_UDEV" USB '^[^#].*power/wakeup' \
'# Managed by dotfiles-arch (setup-gnome.sh)
# Allow USB keyboards/mice (and hubs) to wake from suspend — closed-lid KVM use.
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{bInterfaceClass}=="03", ATTR{power/wakeup}="enabled"
ACTION=="add|change", SUBSYSTEM=="usb", ATTR{bDeviceClass}=="09", ATTR{power/wakeup}="enabled"
ACTION=="add|change", SUBSYSTEM=="usb", KERNEL=="usb[0-9]*", ATTR{power/wakeup}="enabled"' \
    /etc/udev/rules.d/*.rules /run/udev/rules.d/*.rules
print_info_message "Owned USB wake policy takes effect on the next device add/change or reboot"

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

# Sources were preflighted, acquired, and validated against GNOME_SHELL_VERSION
# before shared desktop settings changed. No global compatibility bypass.
print_warning_message "New extensions need a log out/in before GNOME Shell discovers them."

# --------------------------
# Dash to Panel — full-width top bar, small centered icons, every monitor
# --------------------------

DTP_SCHEMA="org.gnome.shell.extensions.dash-to-panel"
print_info_message "Configuring Dash to Panel (always-visible top bar)"

# Always show the panel; put it on every monitor.
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" intellihide false
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" multi-monitors true
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" show-favorites true
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" show-favorites-all-monitors true
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" show-running-apps true
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" stockgs-keep-dash false
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" stockgs-keep-top-panel false
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-element-positions-monitors-sync true

# Full-width top panels; small height; centered along the edge.
# Per-monitor JSON uses index "0" (+ sync) so secondary displays inherit.
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-position TOP
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-size 32
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-positions '{"0":"TOP"}'
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-lengths '{"0":100}'
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-anchors '{"0":"MIDDLE"}'
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-sizes '{"0":32}'

# Taskbar icons centered; Activities hidden; clock/system tray on the right.
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" panel-element-positions \
  '{"0":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"centerMonitor"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]}'

# Compact icons
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" appicon-margin 4
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" appicon-padding 2
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" tray-padding 2
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" status-icon-padding 2

# Do not steal Super+Q (close) or Super+1–9 (workspaces).
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" hot-keys false
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" shortcut "[]"
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" shortcut-text ''
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" intellihide-key-toggle "[]"
gnome_extension_setting dash-to-panel@jderose9.github.com "$DTP_SCHEMA" intellihide-key-toggle-text ''

# GPaste uses the same D-Bus/user-service name on both distros. Never substitute
# another clipboard app or report success when its required service is absent.
if ! command -v gpaste-client >/dev/null || ! gnome_service_loaded user org.gnome.GPaste.service; then
    print_error_message "Required GPaste client/service unavailable; clipboard history cannot be configured"
    exit 1
fi
systemctl --user start org.gnome.GPaste.service
gnome_extension_setting GPaste@gnome-shell-extensions.gnome.org org.gnome.GPaste images-support true
gnome_extension_setting GPaste@gnome-shell-extensions.gnome.org org.gnome.GPaste max-history-size 100
# GPaste 51 removed this cosmetic UI limit; history size and Super+V stay required.
gnome_extension_setting GPaste@gnome-shell-extensions.gnome.org org.gnome.GPaste max-displayed-history-size 20 true
# Super+V uses gpaste-client, independent of the shell extension accelerator.
gnome_extension_setting GPaste@gnome-shell-extensions.gnome.org org.gnome.GPaste show-history ''

# Configure Pop Shell settings
print_info_message "Configuring Pop Shell tiling behavior"

# Floating by default; Super+Y toggles auto-tiling for the workspace
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell tile-by-default false

# Explicitly bind Super+Y (toggle auto-tiling for the workspace)
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell toggle-tiling "['<Super>y']"
# Float / unfloat focused window
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell toggle-floating "['<Super>g']"

# No gaps / no rounded active-hint when tiling is enabled
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell gap-inner 0
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell gap-outer 0
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell smart-gaps false

# Active hint outline (no border radius)
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell hint-color-rgba 'rgba(147, 153, 178, 0.5)'
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell active-hint true
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell active-hint-border-radius 0

# Clear Pop Shell's Super+Return keybinding (conflicts with terminal launcher).
# Rebind tile adjustment mode to Super+Escape instead.
print_info_message "Clearing Pop Shell keybindings that conflict with our shortcuts"
# The shared app launcher is GNOME's grid; do not expose Pop's optional external
# pop-launcher dependency alongside GNOME's Super+Space app grid.
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell activate-launcher "[]"
gnome_extension_setting pop-shell@system76.com org.gnome.shell.extensions.pop-shell tile-enter "['<Super>Escape']"

# Super+Ctrl+Up/Down must NOT switch workspaces (GNOME default steals these chords)
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-up "[]"
gsettings set org.gnome.desktop.wm.keybindings switch-to-workspace-down "[]"

# Super+Ctrl+Arrows: unified "push window".
# - Tiled: Pop Shell tile-move-*-global (move in layout; edge hops monitor)
# - Floating: Mutter half-snap (Left/Right) + move-to-monitor (Up/Down)
# Binding both owners to the same chords double-fires (snap-back).
# rebind-window-push picks one based on tile-by-default; --watch tracks Super+Y.
print_info_message "Configuring Super+Ctrl+Arrows window push (tiling-aware)"
REBIND_WINDOW_PUSH="$DF_SCRIPT_DIR/../home/.local/bin/rebind-window-push"
if [[ ! -f "$REBIND_WINDOW_PUSH" ]]; then
    REBIND_WINDOW_PUSH="$USER_HOME_DIR/.local/bin/rebind-window-push"
fi
if [[ -f "$REBIND_WINDOW_PUSH" ]]; then
    core_cli_link_allowed "$REBIND_WINDOW_PUSH" "$USER_HOME_DIR/.local/bin/rebind-window-push" || {
        print_error_message "rebind-window-push source conflict; user file preserved"
        exit 1
    }
    mkdir -p "$USER_HOME_DIR/.local/bin"
    ln -sfnT "$REBIND_WINDOW_PUSH" "$USER_HOME_DIR/.local/bin/rebind-window-push"
    # Compat name from earlier revisions, only when absent or already ours.
    if core_cli_link_allowed "$REBIND_WINDOW_PUSH" "$USER_HOME_DIR/.local/bin/rebind-monitor-moves"; then
        ln -sfnT "$REBIND_WINDOW_PUSH" "$USER_HOME_DIR/.local/bin/rebind-monitor-moves"
    fi
    bash "$REBIND_WINDOW_PUSH"
    # Restart watcher so sync always picks up script changes (avoid stale --watch).
    while IFS= read -r pid; do
        [[ -r "/proc/$pid/cmdline" ]] || continue
        cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
        if [[ "$cmd" == *"/rebind-window-push"* && "$cmd" == *"--watch"* && "$cmd" != *"-c"* ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    done < <(pgrep -u "$(id -u)" -f 'rebind-window-push' 2>/dev/null || true)
    sleep 0.2
    nohup bash "$REBIND_WINDOW_PUSH" --watch >/dev/null 2>&1 &
else
    print_warning_message "rebind-window-push not found — link dotfiles, then re-run setup-gnome.sh"
fi

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
CUSTOM_KB_EMOJI="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI name 'Emoji Picker'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI command 'gnome-characters'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_EMOJI binding '<Super>period'

# Super+T toggles Voxtype dictation (voxtype-bin, see setup-voxtype.sh).
# GNOME/Wayland has no key-release shortcut event, so this drives voxtype's
# toggle mode rather than true push-to-talk; voxtype's own hotkey is
# disabled in its config so the two don't fight over the same key.
CUSTOM_KB_VOXTYPE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/"
if command -v voxtype &> /dev/null; then
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_VOXTYPE name 'Voxtype Toggle Dictation'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_VOXTYPE command 'voxtype record toggle'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$CUSTOM_KB_VOXTYPE binding '<Super>t'
    VOXTYPE_CUSTOM_KEYBINDINGS=", '$CUSTOM_KB_VOXTYPE'"
else
    VOXTYPE_CUSTOM_KEYBINDINGS=""
fi

# Update the custom keybindings list (no empty custom0; Super+E uses built-in Home)
CUSTOM_KEYBINDINGS="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"
if [[ -n "$VOXTYPE_CUSTOM_KEYBINDINGS" ]]; then
    CUSTOM_KEYBINDINGS="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" shortcuts "$CUSTOM_KEYBINDINGS" \
        "$CUSTOM_KB_TERMINAL" "$CUSTOM_KB_EMOJI" "$CUSTOM_KB_BROWSER" "$CUSTOM_KB_CLIPBOARD" "$CUSTOM_KB_VOXTYPE")"
else
    CUSTOM_KEYBINDINGS="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" shortcuts "$CUSTOM_KEYBINDINGS" \
        "$CUSTOM_KB_TERMINAL" "$CUSTOM_KB_EMOJI" "$CUSTOM_KB_BROWSER" "$CUSTOM_KB_CLIPBOARD")"
fi
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$CUSTOM_KEYBINDINGS"

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
print_info_message "  - Push window (floating): Super+Ctrl+Left/Right half-snap; Up/Down other monitor"
print_info_message "  - Push window (tiled): Super+Ctrl+Arrows rearrange; edge hops monitor"
print_info_message "    (auto-rebinds on Super+Y via rebind-window-push)"
print_info_message "  - Pop Shell toggle auto-tiling (off by default): Super+Y"
print_info_message "  - Pop Shell float focused window: Super+G"
print_info_message "  - Pop Shell tile adjustment mode: Super+Escape"
print_info_message "  - Switch windows: Alt+Tab"
print_info_message ""
print_info_message "Application Launchers:"
print_info_message "  - Top app bar (Dash to Panel): always visible, every monitor"
print_info_message "  - App Launcher: Super+Space"
print_info_message "  - Terminal: Super+Return"
print_info_message "  - File Explorer: Super+E"
print_info_message "  - Browser: Super+B"
print_info_message "  - Clipboard history (GPaste): Super+V"
print_info_message "  - Emoji picker: Super+."
print_info_message "  - Voxtype dictation toggle: Super+T"
print_info_message "  - Screenshot UI: Super+Shift+S (or Print)"
print_info_message ""
print_warning_message "Log out and back in so GNOME reloads extensions (Dash to Panel, GPaste, AppIndicator, Pop Shell)."
print_warning_message "Until then the top app bar / Super+V / Super+Y / tray icons may not work."

# --------------------------
# Installation Complete
# --------------------------

echo ""
print_info_message "GNOME desktop settings configured; log out/in to load validated extensions"
if [[ "$GNOME_POLICIES_DEFERRED" == true ]]; then
    print_warning_message "External machine policies were preserved; deferred policies were not applied"
fi
echo ""
print_info_message "Theme settings applied:"
print_info_message "  - GTK Theme: $CATPPUCCIN_THEME_NAME"
print_info_message "  - Icon Theme: Papirus-Dark (Catppuccin colors)"
print_info_message "  - Color Scheme: Dark"
echo ""
print_info_message "You may need to:"
print_info_message "  1. Log out and log back in for all changes to take effect"
print_info_message "  2. Open GNOME Tweaks to fine-tune appearance settings"

echo ""
print_info_message "To customize further, run: gnome-tweaks"

print_tool_setup_complete "GNOME with Catppuccin Theme"
