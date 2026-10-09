#!/bin/bash

# -------------------------
# GitHub CLI Setup for rolling Arch / Ubuntu 26.04
# -------------------------

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

print_tool_setup_start "GitHub CLI"

ensure_core_cli github-cli
gh --version

print_info_message ""
print_info_message "Next step: authenticate with  gh auth login"

print_tool_setup_complete "GitHub CLI"
