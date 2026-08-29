#!/bin/bash

# --------------------------
# Setup Zed for Arch Linux
# --------------------------
# Zed is installed from the official Arch repos (extra).
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

print_tool_setup_start "Zed"

# --------------------------
# Clean up a stray non-package Zed install (~/.local/zed.app)
# --------------------------
# Some machines may have a manually-installed, self-updating Zed under
# ~/.local/zed.app (with a ~/.local/bin/zed shim) from before the official
# pacman package existed. It holds Zed's single-instance lock, so `zed`/
# `zeditor` launches can silently be served by that stray build instead of
# the pacman-managed one — including a version whose settings schema no
# longer matches config/zed/settings.json (e.g. it rejected a value pacman's
# zeditor accepts, causing user settings to fail to load entirely). Remove
# it so the pacman-installed zeditor is always the one that runs.
LEGACY_ZED_APP_DIR="$USER_HOME_DIR/.local/zed.app"
LEGACY_ZED_SHIM="$USER_HOME_DIR/.local/bin/zed"

if [ -L "$LEGACY_ZED_SHIM" ] && [[ "$(readlink -f "$LEGACY_ZED_SHIM" 2>/dev/null)" == "$LEGACY_ZED_APP_DIR"/* ]]; then
    print_action_message "Removing stray Zed shim: $LEGACY_ZED_SHIM"
    rm -f "$LEGACY_ZED_SHIM"
fi

if [ -d "$LEGACY_ZED_APP_DIR" ] && [ -x "$LEGACY_ZED_APP_DIR/libexec/zed-editor" ]; then
    if pgrep -f "$LEGACY_ZED_APP_DIR/libexec/zed-editor" &>/dev/null; then
        print_warning_message "A Zed process from $LEGACY_ZED_APP_DIR is currently running — quit it manually if $LEGACY_ZED_APP_DIR reappears after removal"
    fi
    print_action_message "Removing stray manual Zed install: $LEGACY_ZED_APP_DIR (superseded by the pacman package)"
    rm -rf "$LEGACY_ZED_APP_DIR"
fi

# The manual installer also dropped its own desktop entry into
# ~/.local/share/applications, which — being a user data dir — takes
# priority over the pacman package's /usr/share/applications entry of the
# same ID. If Exec/TryExec/Icon in it point under $LEGACY_ZED_APP_DIR (now
# removed above, or removed on a prior run), it's a dead entry: GNOME hides
# it from the app grid (TryExec target missing) and its Icon path resolves
# to nothing, showing a generic gear. Remove it so the system entry wins.
LEGACY_ZED_DESKTOP_FILE="$USER_HOME_DIR/.local/share/applications/dev.zed.Zed.desktop"
USER_APPLICATIONS_DIR="$USER_HOME_DIR/.local/share/applications"

if [ -f "$LEGACY_ZED_DESKTOP_FILE" ] && grep -q "$LEGACY_ZED_APP_DIR" "$LEGACY_ZED_DESKTOP_FILE" 2>/dev/null; then
    print_action_message "Removing stray Zed desktop entry: $LEGACY_ZED_DESKTOP_FILE (pointed at the removed manual install)"
    rm -f "$LEGACY_ZED_DESKTOP_FILE"
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$USER_APPLICATIONS_DIR" &>/dev/null || true
    fi
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -qf "$USER_HOME_DIR/.local/share/icons/hicolor" &>/dev/null || true
    fi
fi

# --------------------------
# Install Zed via pacman
# --------------------------

# Check if Zed is already installed
if command -v zeditor &> /dev/null; then
    print_info_message "Zed is already installed. Skipping installation."
    print_info_message "Installed version: $(pacman -Q zed 2>/dev/null | awk '{print $2}')"
else
    print_info_message "Installing Zed from the official repos"

    ensure_pacman_pkgs zed

    if command -v zeditor &> /dev/null; then
        print_info_message "Zed installed successfully"
        print_info_message "You can launch Zed from your application menu or run: zeditor"
        echo ""
        print_info_message "To update packages safely, run:"
        print_info_message "  dfa-update-system"
        print_info_message "  # or: bash scripts/update-system.sh"
    else
        print_error_message "Zed installation failed"
        print_info_message "You can manually install with: pacman -S zed"
    fi
fi

print_tool_setup_complete "Zed"
