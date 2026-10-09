#!/bin/bash

# --------------------------
# Setup opencode CLI for Arch and Ubuntu
# --------------------------
# Arch uses [extra]; Ubuntu uses the stable opencode-ai user npm package.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "opencode"

ensure_harness_cli opencode || exit $?

if command -v opencode &>/dev/null; then
  print_success_message "opencode available as: $(command -v opencode)"
  opencode --version 2>/dev/null || true
else
  print_error_message "opencode installation may have failed"
  exit 1
fi

print_tool_setup_complete "opencode"
