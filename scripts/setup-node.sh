#!/bin/bash

# --------------------------
# Setup NVM and Node.js for Arch
# --------------------------
# NVM lives at ~/.config/nvm (same path as home/.bashrc).
# The official installer is told not to modify shell rc files (PROFILE=/dev/null)
# because ~/.bashrc is a symlink into this repo.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "NVM and Node.js"

ensure_pacman_pkgs curl

NVM_DIR="$(nvm_dir)"
export NVM_DIR
mkdir -p "$NVM_DIR"

# Migrate legacy ~/.nvm if present
load_nvm || true

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  print_action_message "Installing NVM v0.40.3 into $NVM_DIR"
  # Do not append to the symlinked ~/.bashrc
  PROFILE=/dev/null curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
else
  print_info_message "NVM already installed at $NVM_DIR"
fi

if ! load_nvm; then
  print_error_message "NVM not available after install ($NVM_DIR/nvm.sh missing)"
  exit 1
fi

print_info_message "Installing Node.js LTS via NVM"
nvm install --lts
nvm alias default 'lts/*'

print_info_message "Node.js version: $(node --version)"
print_info_message "npm version: $(npm --version)"
print_info_message "NVM version: $(nvm --version)"
print_info_message "NVM_DIR=$NVM_DIR (loaded from ~/.bashrc in new shells)"

print_tool_setup_complete "NVM and Node.js"
