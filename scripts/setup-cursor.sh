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

# cursor-cli only ships /usr/bin/cursor-agent; keep `agent` available for Herdr and muscle memory.
if command -v cursor-agent &>/dev/null && [ ! -e "$USER_HOME_DIR/.local/bin/agent" ]; then
    AGENT_BIN="$(command -v cursor-agent)"
    print_action_message "Linking 'agent' → $AGENT_BIN"
    ln -sfn "$AGENT_BIN" "$USER_HOME_DIR/.local/bin/agent" 2>/dev/null \
        || sudo ln -sfn "$AGENT_BIN" "$USER_HOME_DIR/.local/bin/agent" \
        || print_warning_message "Could not create 'agent' shim in $USER_HOME_DIR/.local/bin"
fi

if command -v cursor-agent &>/dev/null; then
    print_success_message "Cursor Agent CLI available: $(command -v cursor-agent) ($(cursor-agent --version 2>/dev/null | head -1))"
    # Wire Herdr integration when Herdr is already present (bootstrap installs cursor before herdr;
    # re-runs / sync also cover the reverse order)
    if command -v herdr &>/dev/null; then
        mkdir -p "${CURSOR_CONFIG_DIR:-$USER_HOME_DIR/.cursor}"
        print_info_message "Installing Herdr Cursor Agent integration"
        herdr integration install cursor 2>/dev/null \
            || print_warning_message "Could not install Herdr Cursor integration (run: herdr integration install cursor)"
    fi
else
    print_warning_message "cursor-agent not on PATH — check that cursor-cli installed (yay -S cursor-cli)"
fi

print_info_message "Settings are linked to ~/.config/Cursor/User/ via link-dotfiles.sh"
print_tool_setup_complete "Cursor IDE"
