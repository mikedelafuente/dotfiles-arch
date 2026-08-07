#!/bin/bash

# --------------------------
# Setup Claude Code CLI for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Claude Code"

# Prefer user-level NVM npm (never sudo npm — mixes root globals with NVM).
if ! load_nvm || ! command -v npm &>/dev/null; then
  print_error_message "npm not found. Run setup-node.sh first (NVM at ~/.config/nvm)."
  exit 1
fi

if command -v claude &>/dev/null; then
  print_info_message "Claude Code is already installed: $(command -v claude)"
else
  print_action_message "Installing Claude Code via user npm (no sudo)"
  npm install -g @anthropic-ai/claude-code
fi

if command -v claude &>/dev/null; then
  print_success_message "Claude Code available as: $(command -v claude)"
  claude --version 2>/dev/null || true
else
  print_error_message "Claude Code installation may have failed"
  exit 1
fi

print_tool_setup_complete "Claude Code"
