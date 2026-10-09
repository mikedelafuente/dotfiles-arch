#!/bin/bash

# --------------------------
# Setup Neovim for rolling Arch / Ubuntu 26.04
# --------------------------
# This script sets up a modern, beginner-friendly Neovim configuration with:
#   - LSP support for multiple languages (Lua, Python, JS/TS, Rust, Go, PHP, C#)
#   - Treesitter for syntax highlighting
#   - Telescope for fuzzy finding
#   - Auto-completion with nvim-cmp
#   - Which-key for discovering keybindings
#   - File explorer and statusline
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

print_tool_setup_start "Neovim"

# --------------------------
# Install Neovim
# --------------------------

REPO_NVIM_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)/config/nvim"
NVIM_CONFIG_DIR="$USER_HOME_DIR/.config/nvim"
editor_config_allowed "$REPO_NVIM_DIR" "$NVIM_CONFIG_DIR" || {
    print_error_message "Neovim config conflict: $NVIM_CONFIG_DIR; preserved"
    exit 1
}

# Node stays user-owned through the existing NVM setup; do not install distro Node.
load_nvm || true
command -v node &>/dev/null || {
    print_error_message "Node.js is required by the configured LSP servers; run scripts/setup-node.sh first"
    exit 1
}

for app in git fd ripgrep curl jq wl-clipboard xsel; do
    ensure_core_cli "$app" || exit 1
done
NEOVIM_DEPS=(gcc make tar gzip unzip ca-certificates)
case "$WORKSTATION_DISTRO" in
    arch) NEOVIM_DEPS+=(python python-pynvim python-pip) ;;
    ubuntu) NEOVIM_DEPS+=(python3 python3-pynvim python3-venv python3-pip) ;;
esac
ensure_native_pkgs "${NEOVIM_DEPS[@]}" || exit 1
ensure_editor_tool nvim || exit 1
ensure_editor_tool tree-sitter || exit 1
link_editor_config "$REPO_NVIM_DIR" "$NVIM_CONFIG_DIR" || exit 1

# --------------------------
# Configuration Files
# --------------------------

print_info_message "Neovim configuration files are managed in the dotfiles repository"
print_info_message "Location: $(cd "$CURRENT_FILE_DIR/.." && pwd)/config/nvim"
print_info_message "Shared configuration linked at $NVIM_CONFIG_DIR"

# Standalone setup retains the same per-file links as link-dotfiles.sh.

print_action_message "Neovim setup complete!"
print_action_message ""
print_action_message "Next steps:"
print_action_message "  1. Refresh native and managed upstream tools with dfa-update-system --force"
print_action_message "  2. Start Neovim with 'nvim'"
print_action_message "  3. Plugins will install automatically on first launch"
print_action_message "  4. Run ':Mason' to install additional LSP servers"
print_action_message "  5. Run ':checkhealth' to verify everything is working"
print_action_message ""
print_action_message "Quick start:"
print_action_message "  - Press <Space> to see available commands (leader key)"
print_action_message "  - Press <Space>ff to find files"
print_action_message "  - Press <Space>e to toggle file explorer"
print_action_message "  - Press K on a symbol to see documentation"

print_tool_setup_complete "Neovim"
