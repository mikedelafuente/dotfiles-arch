#!/bin/bash

# --------------------------
# Setup Herdr (agent-friendly terminal multiplexer)
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

print_tool_setup_start "Herdr"

# Prefer AUR package only (no curl|bash installer)
if ! command -v herdr &> /dev/null; then
    if ! ensure_yay_installed; then
        print_error_message "yay is required to install Herdr (herdr-bin)"
        exit 1
    fi
    print_info_message "Installing Herdr via yay (herdr-bin)"
    ensure_yay_pkgs herdr-bin
else
    print_info_message "Herdr is already installed. Skipping installation."
fi

if ! command -v herdr &> /dev/null; then
    print_error_message "Herdr installation failed"
    exit 1
fi

print_info_message "Herdr version: $(herdr --version 2>/dev/null || herdr -V 2>/dev/null || echo unknown)"

# Ensure Cursor config dir exists (required by Herdr's cursor integration install)
mkdir -p "${CURSOR_CONFIG_DIR:-$USER_HOME_DIR/.cursor}"

# Official Herdr integrations for agents we install by default
if command -v claude &>/dev/null; then
    print_info_message "Installing Herdr Claude integration"
    herdr integration install claude 2>/dev/null \
        || print_warning_message "Could not install Claude integration (run later: herdr integration install claude)"
fi

# Cursor Agent CLI — Herdr looks for `cursor-agent` on PATH (also provided as `agent`)
if command -v cursor-agent &>/dev/null || command -v agent &>/dev/null; then
    print_info_message "Installing Herdr Cursor Agent integration"
    herdr integration install cursor 2>/dev/null \
        || print_warning_message "Could not install Cursor integration (run later: herdr integration install cursor)"
else
    print_info_message "cursor-agent not on PATH yet — skip Herdr Cursor integration (re-run setup-herdr.sh after Cursor Agent CLI is installed)"
fi

print_info_message "Installed integrations:"
herdr integration status 2>/dev/null | grep -E 'current|outdated' || true

print_info_message "Config: ~/.config/herdr/config.toml (Catppuccin theme via linked dotfiles)"
print_info_message "Usage: herdr   (attach/create session); prefix+q detaches"
print_info_message "Agents: herdr agent start <name> -- cursor   (or claude)"

print_tool_setup_complete "Herdr"
