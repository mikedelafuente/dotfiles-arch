#!/bin/bash

# --------------------------
# Setup Cursor IDE + Agent CLI for Arch Linux
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

print_tool_setup_start "Cursor IDE"

# Ensure ~/.local/bin exists and is on PATH for the `agent` compat shim
mkdir -p "$USER_HOME_DIR/.local/bin"
case ":$PATH:" in
  *":$USER_HOME_DIR/.local/bin:"*) ;;
  *) export PATH="$USER_HOME_DIR/.local/bin:$PATH" ;;
esac

if command -v cursor &> /dev/null; then
    print_info_message "Cursor is already installed. Skipping IDE installation."
    cursor --version 2>/dev/null || true
else
    print_action_message "Installing Cursor via yay (cursor-bin)"
    if ! ensure_yay_installed; then
        print_error_message "yay is required to install Cursor from the AUR"
        exit 1
    fi
    ensure_yay_pkgs cursor-bin
fi

if command -v cursor &> /dev/null; then
    print_success_message "Cursor is available as: $(command -v cursor)"
else
    print_error_message "Cursor installation may have failed"
    exit 1
fi

# --------------------------
# Wayland/Ozone workaround for GPU-less (Intel-only / no dGPU) machines
# --------------------------
# Cursor is an Electron app; on Wayland with only an integrated GPU (no NVIDIA/AMD
# dGPU) it's prone to sluggish rendering and a hang-on-quit caused by Electron's
# native-Wayland (Ozone) backend, not GPU compositing itself (disable-hardware-acceleration
# in argv.json alone does not fix this). Forcing the Chromium/Electron ozone platform to
# x11 (XWayland) works around it. Gated on actual PCI hardware (has_nvidia_hardware), not
# installed driver packages — a machine can have nvidia-* packages left over from a prior
# INSTALL_NVIDIA=true run with no NVIDIA GPU physically present. Skip entirely when NVIDIA
# hardware is present, where the default path is already exercised and known-good.
CURSOR_SYSTEM_DESKTOP_FILE="/usr/share/applications/cursor.desktop"
CURSOR_USER_APPLICATIONS_DIR="$USER_HOME_DIR/.local/share/applications"
CURSOR_OVERRIDE_DESKTOP_FILE="$CURSOR_USER_APPLICATIONS_DIR/cursor.desktop"
CURSOR_CONFIG_DIR="${CURSOR_CONFIG_DIR:-$USER_HOME_DIR/.cursor}"
CURSOR_ARGV_JSON="$CURSOR_CONFIG_DIR/argv.json"

# Idempotently force "disable-hardware-acceleration": true in argv.json (JSONC — comments
# allowed, so this can't be round-tripped through jq). Handles: key absent, present-and-false,
# present-and-true (no-op), and commented-out.
ensure_cursor_disable_hardware_acceleration() {
    local file="$CURSOR_ARGV_JSON"

    if [ ! -f "$file" ]; then
        mkdir -p "$(dirname "$file")"
        cat > "$file" <<'EOF'
// This configuration file allows you to pass permanent command line arguments to VS Code.
// Only a subset of arguments is currently supported to reduce the likelihood of breaking
// the installation.
{
	// Use software rendering instead of hardware accelerated rendering.
	// This can help in cases where you see rendering issues in VS Code.
	"disable-hardware-acceleration": true
}
EOF
        print_success_message "Created $file with disable-hardware-acceleration: true"
        return
    fi

    if grep -qE '^\s*"disable-hardware-acceleration"\s*:\s*true\b' "$file"; then
        return
    fi

    if grep -qE '^\s*"disable-hardware-acceleration"\s*:\s*false\b' "$file"; then
        sed -i -E 's/^(\s*)"disable-hardware-acceleration"(\s*:\s*)false\b/\1"disable-hardware-acceleration"\2true/' "$file"
        print_success_message "Set disable-hardware-acceleration: true in $file"
        return
    fi

    if grep -qE '^\s*//\s*"disable-hardware-acceleration"\s*:\s*(true|false)\b' "$file"; then
        sed -i -E 's#^(\s*)//\s*("disable-hardware-acceleration"\s*:\s*)(true|false)\b#\1\2true#' "$file"
        print_success_message "Uncommented disable-hardware-acceleration: true in $file"
        return
    fi

    local close_line
    close_line="$(grep -n '^}$' "$file" | tail -1 | cut -d: -f1)"
    if [ -z "$close_line" ]; then
        print_warning_message "Could not find top-level closing brace in $file — add \"disable-hardware-acceleration\": true manually"
        return
    fi

    local prev_line_num=$((close_line - 1))
    while [ "$prev_line_num" -ge 1 ]; do
        local content
        content="$(sed -n "${prev_line_num}p" "$file")"
        [[ -n "${content// }" ]] && break
        prev_line_num=$((prev_line_num - 1))
    done

    if [ "$prev_line_num" -ge 1 ]; then
        local prev_content
        prev_content="$(sed -n "${prev_line_num}p" "$file")"
        if [[ ! "$prev_content" =~ ,[[:space:]]*$ ]]; then
            sed -i "${prev_line_num}s/[[:space:]]*\$/,/" "$file"
        fi
    fi

    sed -i "${close_line}i\\	\"disable-hardware-acceleration\": true" "$file"
    print_success_message "Added disable-hardware-acceleration: true to $file"
}

if has_nvidia_hardware; then
    if [ -f "$CURSOR_OVERRIDE_DESKTOP_FILE" ]; then
        print_action_message "NVIDIA hardware detected — removing Cursor XWayland override"
        rm -f "$CURSOR_OVERRIDE_DESKTOP_FILE"
        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "$CURSOR_USER_APPLICATIONS_DIR" &>/dev/null || true
        fi
    fi
elif [ -f "$CURSOR_SYSTEM_DESKTOP_FILE" ]; then
    if ! grep -q -- '--ozone-platform=x11' "$CURSOR_OVERRIDE_DESKTOP_FILE" 2>/dev/null; then
        print_action_message "No dedicated GPU detected — forcing Cursor to XWayland via desktop override"
        mkdir -p "$CURSOR_USER_APPLICATIONS_DIR"
        sed -E 's#^Exec=/usr/share/cursor/cursor #Exec=/usr/share/cursor/cursor --ozone-platform=x11 #' \
            "$CURSOR_SYSTEM_DESKTOP_FILE" > "$CURSOR_OVERRIDE_DESKTOP_FILE"
        if command -v update-desktop-database &>/dev/null; then
            update-desktop-database "$CURSOR_USER_APPLICATIONS_DIR" &>/dev/null || true
        fi
        print_success_message "Cursor launcher now forces --ozone-platform=x11 (log out/in or re-login not required; takes effect on next launch)"
    fi
    print_action_message "No dedicated GPU detected — ensuring disable-hardware-acceleration in argv.json"
    ensure_cursor_disable_hardware_acceleration
else
    print_warning_message "Cursor desktop file not found at $CURSOR_SYSTEM_DESKTOP_FILE — skipping XWayland override"
fi

# --------------------------
# Cursor Agent CLI (cursor-cli from the AUR)
# --------------------------
# Managed through yay so it flows via the same guarded `yay -Syu` + IoC scan as
# the rest of the stack. The AUR package blocks the vendor auto-updater by
# chmod -x'ing ~/.local/share/cursor-agent/versions, so any earlier curl|bash
# install living in that tree must be cleared out first — otherwise the two
# installs fight over PATH and the old shims silently break.

AGENT_STATE_DIR="$USER_HOME_DIR/.local/share/cursor-agent"

# Shims may be root-owned when an earlier setup run happened under sudo.
remove_path_entry() {
    rm -rf "$1" 2>/dev/null || sudo rm -rf "$1"
}

remove_legacy_agent_cli() {
    local link
    local removed=false

    for link in "$USER_HOME_DIR/.local/bin/cursor-agent" "$USER_HOME_DIR/.local/bin/agent"; do
        if [ -L "$link" ] && [[ "$(readlink -f "$link" 2>/dev/null)" == "$AGENT_STATE_DIR"/* ]]; then
            print_action_message "Removing curl-installed shim: $link"
            remove_path_entry "$link"
            removed=true
        fi
    done

    if [ -d "$AGENT_STATE_DIR/versions" ]; then
        # cursor-cli leaves this directory non-traversable; restore +x so it can be walked.
        chmod u+rwx "$AGENT_STATE_DIR/versions" 2>/dev/null \
            || sudo chmod u+rwx "$AGENT_STATE_DIR/versions" 2>/dev/null || true
        if [ -n "$(ls -A "$AGENT_STATE_DIR/versions" 2>/dev/null)" ]; then
            print_action_message "Removing curl-installed Agent CLI payload: $AGENT_STATE_DIR/versions"
            remove_path_entry "$AGENT_STATE_DIR/versions"
            removed=true
        fi
    fi

    if [ "$removed" = true ]; then
        print_success_message "Removed curl-installed Cursor Agent CLI"
        hash -r 2>/dev/null || true
    fi
}

remove_legacy_agent_cli

if ! ensure_yay_installed; then
    print_error_message "yay is required to install the Cursor Agent CLI (cursor-cli)"
    exit 1
fi

ensure_yay_pkgs cursor-cli

# cursor-cli only ships /usr/bin/cursor-agent; keep `agent` available for muscle memory.
if command -v cursor-agent &>/dev/null && [ ! -e "$USER_HOME_DIR/.local/bin/agent" ]; then
    AGENT_BIN="$(command -v cursor-agent)"
    print_action_message "Linking 'agent' → $AGENT_BIN"
    ln -sfn "$AGENT_BIN" "$USER_HOME_DIR/.local/bin/agent" 2>/dev/null \
        || sudo ln -sfn "$AGENT_BIN" "$USER_HOME_DIR/.local/bin/agent" \
        || print_warning_message "Could not create 'agent' shim in $USER_HOME_DIR/.local/bin"
fi

if command -v cursor-agent &>/dev/null; then
    print_success_message "Cursor Agent CLI available: $(command -v cursor-agent) ($(cursor-agent --version 2>/dev/null | head -1))"
else
    print_warning_message "cursor-agent not on PATH — check that cursor-cli installed (yay -S cursor-cli)"
fi

# --------------------------
# afterFileEdit hook: reveal edited files in the paired Neovim pane
# --------------------------
# Idempotently ensures nvim-reveal-edit runs after the Agent CLI edits a
# file. Only touches .hooks.afterFileEdit so any other configured hooks are
# left alone. hooks.json is plain JSON (unlike argv.json above, which is
# JSONC), so jq is safe to use directly here.
CURSOR_HOOKS_FILE="$USER_HOME_DIR/.cursor/hooks.json"

ensure_json_hook_registered "$CURSOR_HOOKS_FILE" '{"version": 1, "hooks": {}}' \
  '(.hooks.afterFileEdit // []) | any(.command == "nvim-reveal-edit")' \
  '.version = (.version // 1) | .hooks.afterFileEdit = ((.hooks.afterFileEdit // []) + [{"command": "nvim-reveal-edit"}])' \
  "the Neovim reveal-on-edit afterFileEdit hook"

print_info_message "Settings are linked to ~/.config/Cursor/User/ via link-dotfiles.sh"
print_tool_setup_complete "Cursor IDE"
