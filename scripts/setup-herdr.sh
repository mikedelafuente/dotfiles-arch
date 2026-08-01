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

# Prefer AUR package; fall back to official install script
if ! command -v herdr &> /dev/null; then
    if command -v yay &> /dev/null; then
        print_info_message "Installing Herdr via yay (herdr-bin)"
        yay -S --needed --noconfirm herdr-bin
    else
        print_info_message "Installing Herdr via official install script"
        curl -fsSL https://herdr.dev/install.sh | sh
    fi
else
    print_info_message "Herdr is already installed. Skipping installation."
fi

if ! command -v herdr &> /dev/null; then
    print_error_message "Herdr installation failed"
    exit 1
fi

print_info_message "Herdr version: $(herdr --version 2>/dev/null || herdr -V 2>/dev/null || echo unknown)"

# Install Claude integration when Claude Code is available
if command -v claude &> /dev/null; then
    print_info_message "Installing Herdr Claude integration"
    herdr integration install claude 2>/dev/null \
        || print_warning_message "Could not install Claude integration (run later: herdr integration install claude)"
fi

print_info_message "Config: ~/.config/herdr/config.toml (Catppuccin theme via linked dotfiles)"
print_info_message "Usage: herdr   (attach/create session); prefix+q detaches"

print_tool_setup_complete "Herdr"
