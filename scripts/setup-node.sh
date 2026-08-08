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

ensure_pacman_pkgs curl coreutils

NVM_DIR="$(nvm_dir)"
export NVM_DIR
mkdir -p "$NVM_DIR"

# Migrate legacy ~/.nvm if present
load_nvm || true

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  # Pin version + SHA-256 together. To bump NVM:
  #   curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/vX.Y.Z/install.sh | sha256sum
  # then update NVM_VERSION and NVM_INSTALL_SHA256 below.
  NVM_VERSION="v0.40.3"
  NVM_INSTALL_SHA256="2d8359a64a3cb07c02389ad88ceecd43f2fa469c06104f92f98df5b6f315275f"
  NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

  print_action_message "Installing NVM ${NVM_VERSION} into $NVM_DIR"
  tmp_install="$(mktemp)"
  if ! curl -fsSL "$NVM_INSTALL_URL" -o "$tmp_install"; then
    rm -f "$tmp_install"
    print_error_message "Failed to download NVM install.sh"
    exit 1
  fi
  actual_sha="$(sha256sum "$tmp_install" | awk '{print $1}')"
  if [[ "$actual_sha" != "$NVM_INSTALL_SHA256" ]]; then
    rm -f "$tmp_install"
    print_error_message "NVM install.sh checksum mismatch (got $actual_sha, expected $NVM_INSTALL_SHA256)"
    exit 1
  fi
  # Do not append to the symlinked ~/.bashrc
  PROFILE=/dev/null bash "$tmp_install"
  rm -f "$tmp_install"
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
