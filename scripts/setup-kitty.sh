#!/bin/bash

# --------------------------
# Setup Kitty Terminal for rolling Arch / Ubuntu 26.04
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

print_tool_setup_start "Kitty"

# Preflight config/source conflicts before installing or writing anything.
REPO_KITTY_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)/config/kitty"
KITTY_CONFIG_DIR="$USER_HOME_DIR/.config/kitty"

for dir in "$USER_HOME_DIR/.config" "$KITTY_CONFIG_DIR" "$KITTY_CONFIG_DIR/themes"; do
    if { [[ -e "$dir" || -L "$dir" ]] && [[ ! -d "$dir" ]]; } \
        || { [[ "$dir" != "$USER_HOME_DIR/.config" && -L "$dir" ]] \
            && [[ "$(readlink -f "$dir")" != "$(readlink -f "$REPO_KITTY_DIR${dir#"$KITTY_CONFIG_DIR"}")" ]]; }; then
        print_error_message "Kitty config directory conflict: $dir; preserved"
        exit 1
    fi
done

for relative in kitty.conf themes/mocha.conf; do
    source_file="$REPO_KITTY_DIR/$relative"
    target="$KITTY_CONFIG_DIR/$relative"
    if [[ ! -f "$source_file" ]]; then
        print_error_message "Missing Kitty config: $source_file"
        exit 1
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source_file")" ]] \
            || { [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source_file" "$target"; }; then
            continue
        fi
        print_error_message "Kitty config conflict: $target; preserved (resolve before rerunning)"
        exit 1
    fi
done

kitty_path="$(type -P kitty || true)"
if native_package_installed kitty; then
    if [[ -z "$kitty_path" || "$(readlink -f "$kitty_path")" != "$(readlink -f /usr/bin/kitty)" ]]; then
        print_error_message "Native Kitty is installed but PATH does not select /usr/bin/kitty; resolve the launcher conflict"
        exit 1
    fi
    print_info_message "Keeping native Kitty; update owner: $WORKSTATION_DISTRO system packages"
elif [[ -n "$kitty_path" || -e /usr/bin/kitty || -L /usr/bin/kitty ]]; then
    print_error_message "Kitty source conflict: an unmanaged launcher exists; preserved. No duplicate installation or source fallback."
    exit 1
else
    ensure_native_pkgs kitty || exit 1
    hash -r
    kitty_path="$(type -P kitty || true)"
fi

if ! native_package_installed kitty || [[ -z "$kitty_path" || "$(readlink -f "$kitty_path")" != "$(readlink -f /usr/bin/kitty)" ]] \
    || [[ ! -x /usr/bin/kitty ]]; then
    print_error_message "Native Kitty installation did not provide its required launcher"
    exit 1
fi
kitty_version="$(/usr/bin/kitty --version)" || exit 1
if [[ ! "$kitty_version" =~ ^kitty\ ([0-9]+)\.([0-9]+)\.[0-9]+ ]] \
    || ! (( 10#${BASH_REMATCH[1]} > 0 || 10#${BASH_REMATCH[2]} >= 26 )); then
    print_error_message "Kitty 0.26+ is required for this recipe; update through the native package owner (installation preserved)"
    exit 1
fi
print_info_message "$kitty_version"

# Standalone setup links only Kitty; identical legacy theme copies are retained.
mkdir -p "$KITTY_CONFIG_DIR/themes"
for relative in kitty.conf themes/mocha.conf; do
    target="$KITTY_CONFIG_DIR/$relative"
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        ln -s "$REPO_KITTY_DIR/$relative" "$target"
    fi
done

# --------------------------
# Set Default Terminal for All Available Desktop Environments
# --------------------------

print_info_message "Kitty path: $kitty_path"

print_info_message "Configuring Kitty as default terminal for all available environments..."

# Configure KDE Plasma (if available)
if command -v kwriteconfig5 &> /dev/null || command -v kwriteconfig6 &> /dev/null; then
    print_info_message "Configuring Kitty as default terminal for KDE"

    if command -v kwriteconfig6 &> /dev/null; then
        KWRITECONFIG="kwriteconfig6"
    else
        KWRITECONFIG="kwriteconfig5"
    fi

    $KWRITECONFIG --file kdeglobals --group General --key TerminalApplication kitty
    $KWRITECONFIG --file kdeglobals --group General --key TerminalService ""

    print_info_message "✓ KDE configured"
else
    print_info_message "KDE configuration tools not found. Skipping KDE setup."
fi

# Configure Gnome (if gsettings is available)
if command -v gsettings &> /dev/null; then
    print_info_message "Configuring Kitty as default terminal for Gnome"

    gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg ''

    print_info_message "✓ Gnome configured"
else
    print_info_message "gsettings not found. Skipping Gnome setup."
fi

print_tool_setup_complete "Kitty"
