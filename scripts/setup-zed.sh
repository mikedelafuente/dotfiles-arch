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

# --------------------------
# Make Zed the default handler for text-like files
# --------------------------
# The packaged desktop entry only claims text/plain, application/x-zerosize and
# x-scheme-handler/zed. Everything else a developer opens — JSON, YAML, shell,
# PHP, source files — falls to whatever else registered for it. These xdg-mime
# calls write ~/.config/mimeapps.list, which outranks any desktop entry's own
# MimeType field and survives a pacman upgrade of the zed package.

ZED_DESKTOP_ID="dev.zed.Zed.desktop"

if ! command -v xdg-mime &>/dev/null; then
    print_warning_message "xdg-mime not found — skipping default-application setup"
elif [ ! -r "/usr/share/applications/$ZED_DESKTOP_ID" ]; then
    print_warning_message "No $ZED_DESKTOP_ID in /usr/share/applications — skipping default-application setup"
else
    # Types owned by an app that does the job better than an editor would.
    # text/html belongs to the browser; a double-clicked .html should render.
    MIME_EXCLUDE=(
        text/calendar
        text/html
        text/vcard
        text/x-vcard
    )

    # Every text/* the shared-mime-info database knows about, so a new language
    # picks up Zed without this list being edited.
    ZED_MIME_TYPES=()
    while IFS= read -r mime_xml; do
        mime_type="text/$(basename "$mime_xml" .xml)"
        skip=0
        for excluded in "${MIME_EXCLUDE[@]}"; do
            [ "$mime_type" = "$excluded" ] && skip=1 && break
        done
        [ "$skip" -eq 0 ] && ZED_MIME_TYPES+=("$mime_type")
    done < <(find /usr/share/mime/text -maxdepth 1 -name '*.xml' 2>/dev/null | sort)

    # Text formats the database files under application/* rather than text/*.
    ZED_MIME_TYPES+=(
        application/javascript
        application/json
        application/sql
        application/toml
        application/x-perl
        application/x-php
        application/x-ruby
        application/x-shellscript
        application/x-yaml
        application/xml
        application/yaml
    )

    print_action_message "Setting Zed as the default for ${#ZED_MIME_TYPES[@]} MIME types (text/*, common source formats)"

    if xdg-mime default "$ZED_DESKTOP_ID" "${ZED_MIME_TYPES[@]}" 2>/dev/null; then
        print_success_message "Zed registered as the default text and source-file handler"
    else
        print_warning_message "xdg-mime rejected one or more types — check ~/.config/mimeapps.list"
    fi

    # Folders belong to the file manager. An earlier version of this script
    # claimed inode/directory for Zed, which also captured `xdg-open <dir>`
    # and "Open Folder With". Hand it back, but only from Zed — a different
    # file manager set here is the user's own choice.
    FILE_MANAGER_DESKTOP_ID="org.gnome.Nautilus.desktop"

    if [ "$(xdg-mime query default inode/directory 2>/dev/null)" = "$ZED_DESKTOP_ID" ]; then
        if [ -r "/usr/share/applications/$FILE_MANAGER_DESKTOP_ID" ]; then
            print_action_message "Returning inode/directory to $FILE_MANAGER_DESKTOP_ID (folders open in the file manager, not Zed)"
            xdg-mime default "$FILE_MANAGER_DESKTOP_ID" inode/directory 2>/dev/null \
                || print_warning_message "Could not reset the inode/directory default — check ~/.config/mimeapps.list"
        else
            print_warning_message "Zed owns inode/directory but $FILE_MANAGER_DESKTOP_ID is not installed — leaving it alone"
        fi
    fi

    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$USER_APPLICATIONS_DIR" &>/dev/null || true
    fi
fi

print_tool_setup_complete "Zed"
