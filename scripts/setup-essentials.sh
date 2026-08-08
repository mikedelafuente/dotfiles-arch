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
  htop
  ncdu
  tree
  jq
  net-tools
  btop
  duf
  stow
  shellcheck
  github-cli
  tldr
  fastfetch
  zoxide
)

print_line_break "Installing essential packages"
ensure_pacman_pkgs "${ESSENTIAL_PACKAGES[@]}"

# Intel firmware only when Intel hardware is present (CPU/PCI)
if has_intel_hardware; then
  print_info_message "Intel hardware detected — ensuring linux-firmware-intel"
  ensure_pacman_pkgs linux-firmware-intel
else
  print_info_message "No Intel hardware detected — skipping linux-firmware-intel"
fi

if pacman -Q zoxide &>/dev/null && command -v zoxide &>/dev/null; then
  print_info_message "Initializing zoxide for current session"
  eval "$(zoxide init bash)"
fi

# Refresh the bat theme/syntax cache so the configured theme resolves
if command -v bat &>/dev/null; then
  print_info_message "Rebuilding bat cache"
  bat cache --build >/dev/null 2>&1 || print_warning_message "bat cache --build failed (non-fatal)"
fi

print_tool_setup_complete "Essential Packages"
