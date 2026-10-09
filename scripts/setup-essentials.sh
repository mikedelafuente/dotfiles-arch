#!/bin/bash
# -------------------------
# Setup Essential Packages
# -------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Essential Packages"

REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
core_cli_link_allowed "$REPO_ROOT/config/bat/config" "$USER_HOME_DIR/.config/bat/config" || {
  print_error_message "bat config conflict; preserved"
  exit 1
}

# Keep PACKAGES.md in sync when changing this list
# (also keep aliases/tools listed in home/.bashrc consistent)
ESSENTIAL_PACKAGES=(
  git
  git-delta
  curl
  wget
  xsel
  wl-clipboard
  eza
  starship
  fzf
  ripgrep
  fd
  bat
  glow
  htop
  ncdu
  tree
  jq
  net-tools
  iw
  btop
  duf
  stow
  shellcheck
  github-cli
  tldr
  fastfetch
  zoxide
  bash-completion
  less
  util-linux
)

print_line_break "Installing essential packages"
for app in "${ESSENTIAL_PACKAGES[@]}"; do
  ensure_core_cli "$app" || exit 1
done
link_core_cli_config "$REPO_ROOT/config/bat/config" "$USER_HOME_DIR/.config/bat/config"

# Intel firmware only when Intel hardware is present (CPU/PCI)
if [[ "$WORKSTATION_DISTRO" == arch ]] && has_intel_hardware; then
  print_info_message "Intel hardware detected — ensuring linux-firmware-intel"
  ensure_pacman_pkgs linux-firmware-intel
else
  print_info_message "Skipping Arch Intel firmware; Ubuntu firmware stays with its native/IT owner"
fi

if native_package_installed zoxide && command -v zoxide &>/dev/null; then
  print_info_message "Initializing zoxide for current session"
  eval "$(zoxide init bash)"
fi

# Use the native built-in theme when available, verified upstream data otherwise.
ensure_bat_appearance || exit 1

print_tool_setup_complete "Essential Packages"
