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

# Ensure ~/.local/bin exists and is preferred for agent/cursor-agent shims
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
    if ! command -v yay &> /dev/null; then
        print_error_message "yay is required to install Cursor from the AUR"
        exit 1
    fi
    yay -S --needed --noconfirm cursor-bin
fi

if command -v cursor &> /dev/null; then
    print_success_message "Cursor is available as: $(command -v cursor)"
else
    print_error_message "Cursor installation may have failed"
    exit 1
fi

# Cursor Agent CLI (agent / cursor-agent) — required for Herdr Cursor integration
if command -v cursor-agent &>/dev/null || command -v agent &>/dev/null; then
    print_info_message "Cursor Agent CLI already installed: $(command -v cursor-agent 2>/dev/null || command -v agent)"
    agent --version 2>/dev/null || cursor-agent --version 2>/dev/null || true
else
    print_action_message "Installing Cursor Agent CLI (official installer)"
    curl -fsS https://cursor.com/install | bash \
        || print_warning_message "Cursor Agent CLI install failed — run: curl -fsS https://cursor.com/install | bash"
fi

if command -v cursor-agent &>/dev/null || command -v agent &>/dev/null; then
    print_success_message "Cursor Agent CLI available (agent / cursor-agent)"
    # Wire Herdr integration when Herdr is already present (bootstrap installs cursor before herdr;
    # re-runs / sync also cover the reverse order)
    if command -v herdr &>/dev/null; then
        mkdir -p "${CURSOR_CONFIG_DIR:-$USER_HOME_DIR/.cursor}"
        print_info_message "Installing Herdr Cursor Agent integration"
        herdr integration install cursor 2>/dev/null \
            || print_warning_message "Could not install Herdr Cursor integration (run: herdr integration install cursor)"
    fi
else
    print_warning_message "Cursor Agent CLI not on PATH yet — ensure ~/.local/bin is in PATH"
fi

print_info_message "Settings are linked to ~/.config/Cursor/User/ via link-dotfiles.sh"
print_tool_setup_complete "Cursor IDE"
