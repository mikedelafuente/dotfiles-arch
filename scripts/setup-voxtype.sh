#!/bin/bash

# --------------------------
# Setup Voxtype for Arch Linux
# --------------------------
# Voxtype (https://voxtype.io) is a push-to-talk / toggle voice-to-text
# daemon. Omarchy (basecamp/omarchy) ships it on Hyprland, where the
# compositor supports both the virtual-keyboard protocol (wtype output) and
# key-release events (true push-to-talk, e.g. hold F9). GNOME/Wayland has
# neither: no virtual-keyboard-protocol support (wtype fails, so we install
# dotool instead) and no key-release shortcut event, so we drive voxtype's
# toggle mode from a GNOME custom keybinding (see setup-gnome.sh, Super+T)
# instead of voxtype's own evdev-level hotkey.
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

print_tool_setup_start "Voxtype"

# --------------------------
# Install voxtype + dotool (AUR — no official-repo equivalent exists)
# --------------------------

if command -v voxtype &> /dev/null; then
    print_info_message "Voxtype is already installed. Skipping installation."
else
    print_info_message "Installing Voxtype from AUR (voxtype-bin)"
    ensure_yay_pkgs voxtype-bin
fi

# dotool types on GNOME/KDE Wayland, where voxtype's default wtype output
# driver isn't supported (no virtual-keyboard-protocol support).
if ! command -v dotool &> /dev/null; then
    print_info_message "Installing dotool from AUR (Wayland text-injection fallback for GNOME)"
    ensure_yay_pkgs dotool
fi

if ! command -v voxtype &> /dev/null; then
    print_error_message "Voxtype installation failed"
    print_info_message "You can manually install with: yay -S voxtype-bin (review PKGBUILD first)"
    print_tool_setup_complete "Voxtype"
    exit 0
fi

# --------------------------
# Config: disable voxtype's own hotkey, drive it via GNOME's Super+T instead
# --------------------------

VOXTYPE_CONFIG_DIR="$USER_HOME_DIR/.config/voxtype"
VOXTYPE_CONFIG_FILE="$VOXTYPE_CONFIG_DIR/config.toml"

if [ ! -f "$VOXTYPE_CONFIG_FILE" ]; then
    print_info_message "Writing default Voxtype config ($VOXTYPE_CONFIG_FILE)"
    mkdir -p "$VOXTYPE_CONFIG_DIR"
    cat > "$VOXTYPE_CONFIG_FILE" <<'EOF'
# Managed by dotfiles-arch (scripts/setup-voxtype.sh).
# Toggled via GNOME's Super+T custom keybinding (scripts/setup-gnome.sh),
# not voxtype's own evdev hotkey — GNOME/Wayland offers no key-release
# event for true push-to-talk.
[hotkey]
enabled = false

[output]
mode = "type"
driver_order = ["dotool", "clipboard"]
EOF
elif ! grep -q '^\[hotkey\]' "$VOXTYPE_CONFIG_FILE" 2>/dev/null; then
    print_warning_message "Existing $VOXTYPE_CONFIG_FILE has no [hotkey] section — leaving it as-is"
    print_info_message "Add 'enabled = false' under [hotkey] so it doesn't fight the Super+T toggle binding"
fi

if [ -n "${SUDO_USER-}" ]; then
    sudo chown -R "$SUDO_USER" "$VOXTYPE_CONFIG_DIR"
fi

# --------------------------
# Download the default speech model (idempotent)
# --------------------------

print_info_message "Ensuring the default Voxtype speech model is downloaded"
voxtype setup --download --no-post-install || print_warning_message "voxtype setup --download failed — run it manually to fetch the speech model"

# GPU-accelerate transcription when a Vulkan ICD is present (any vendor).
if [[ -d /usr/share/vulkan/icd.d ]] && find /usr/share/vulkan/icd.d -maxdepth 1 -name "*.json" -print -quit 2>/dev/null | grep -q .; then
    print_info_message "Vulkan detected — enabling GPU transcription"
    voxtype setup gpu --enable || print_warning_message "voxtype setup gpu --enable failed — transcription will stay on CPU"
fi

# --------------------------
# Enable the systemd --user service
# --------------------------

voxtype setup systemd || print_warning_message "voxtype setup systemd failed — start the daemon manually with: voxtype"

print_info_message "Toggle dictation with Super+T (configured in setup-gnome.sh)"

print_tool_setup_complete "Voxtype"
