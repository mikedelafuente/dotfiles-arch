#!/bin/bash

# Minimal post-install after archinstall:
# - enable multilib
# - optionally install NVIDIA drivers (detect / saved preference / prompt)
# - install Kitty + base tooling
#
# After this, run: bash scripts/bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Prefer shared helpers when available
if [ -r "$SCRIPT_DIR/scripts/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/scripts/dotheader.sh"
fi

# --------------------------
# Enable multilib
# --------------------------

PACMAN_CONF="/etc/pacman.conf"

if [ ! -f "$PACMAN_CONF" ]; then
  echo "Error: $PACMAN_CONF not found."
  exit 1
fi

if grep -q '^\[multilib\]' "$PACMAN_CONF"; then
  echo "[multilib] already enabled in $PACMAN_CONF"
else
  sudo sed -i '/^#\[multilib\]/{
    s/^#//
    n
    s/^#//
}' "$PACMAN_CONF"
  echo "[multilib] and its Include line have been uncommented in $PACMAN_CONF"
fi

sudo pacman -Syu --noconfirm

# --------------------------
# NVIDIA (conditional)
# --------------------------
# Use --yes when INSTALL_NVIDIA is already saved (re-runs); otherwise prompt.

if [ -r "$SCRIPT_DIR/scripts/setup-nvidia.sh" ]; then
  load_bootstrap_config 2>/dev/null || true
  if [ "${INSTALL_NVIDIA:-}" = "true" ] || [ "${INSTALL_NVIDIA:-}" = "false" ]; then
    bash "$SCRIPT_DIR/scripts/setup-nvidia.sh" --yes
  else
    bash "$SCRIPT_DIR/scripts/setup-nvidia.sh"
  fi
else
  echo "Warning: scripts/setup-nvidia.sh not found; skipping NVIDIA setup"
fi

# --------------------------
# Base packages
# --------------------------

sudo pacman -S --needed --noconfirm kitty git base-devel linux-headers man-db
sudo mandb

echo ""
echo "post_install complete. Next: bash scripts/bootstrap.sh"
