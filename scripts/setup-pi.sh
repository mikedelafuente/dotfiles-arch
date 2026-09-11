#!/bin/bash

# --------------------------
# Setup pi (Pi coding agent) CLI for Arch Linux
# --------------------------
# Installs the stock published package. See pi-dev/README.md for the plan to
# switch this to a local/custom build.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "pi"

# Prefer user-level NVM npm (never sudo npm — mixes root globals with NVM).
if ! load_nvm || ! command -v npm &>/dev/null; then
  print_error_message "npm not found. Run setup-node.sh first (NVM at ~/.config/nvm)."
  exit 1
fi

if command -v pi &>/dev/null; then
  print_info_message "pi is already installed: $(command -v pi)"
else
  # Per https://pi.dev/docs/latest: pi needs no install scripts for a normal
  # npm install, so lifecycle scripts stay blocked (unlike Claude Code).
  print_action_message "Installing pi via user npm (no sudo)"
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent
fi

if command -v pi &>/dev/null; then
  print_success_message "pi available as: $(command -v pi)"
  pi --version 2>/dev/null || true
else
  print_error_message "pi installation may have failed"
  exit 1
fi

print_tool_setup_complete "pi"
