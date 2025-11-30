#!/bin/bash

# --------------------------
# Setup Claude Code CLI for Arch Linux
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

# --------------------------
# Setup Claude Code
# --------------------------

# Install Claude Code via npm
if ! command -v claude-code &> /dev/null; then
    print_info_message "Installing Claude Code..."
    sudo npm install -g @anthropic-ai/claude-code
else
    print_info_message "Claude Code is already installed."
fi 

# --------------------------
# Complete Claude Code Setup
# --------------------------


