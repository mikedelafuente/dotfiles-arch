#!/bin/bash

# --------------------------
# Setup Claude Code CLI for Arch Linux
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

print_tool_setup_start "Claude Code"

if ! command -v npm &> /dev/null; then
    print_error_message "npm is not installed. Please run setup-node.sh first."
    exit 1
fi

# Binary provided by @anthropic-ai/claude-code is `claude`
if ! command -v claude &> /dev/null; then
    print_info_message "Installing Claude Code via npm..."
    sudo npm install -g @anthropic-ai/claude-code
else
    print_info_message "Claude Code is already installed."
fi

if command -v claude &> /dev/null; then
    print_success_message "Claude Code available as: $(command -v claude)"
    claude --version 2>/dev/null || true
else
    print_error_message "Claude Code installation may have failed"
    exit 1
fi

print_tool_setup_complete "Claude Code"
