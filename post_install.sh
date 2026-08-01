#!/bin/bash

# Minimal post-install after archinstall:
# - enable multilib
# - optionally install NVIDIA drivers (only when already present from archinstall,
#   NVIDIA hardware is detected, or the user confirms)
# - install Kitty + base tooling

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# --------------------------
# Enable multilib
# --------------------------

PACMAN_CONF="/etc/pacman.conf"

if [ ! -f "$PACMAN_CONF" ]; then
    echo "Error: $PACMAN_CONF not found."
    exit 1
fi

sudo sed -i '/^#\[multilib\]/{
    s/^#//
    n
    s/^#//
}' "$PACMAN_CONF"

echo "[multilib] and its Include line have been uncommented in $PACMAN_CONF"

sudo pacman -Syu --noconfirm

# --------------------------
# NVIDIA (conditional)
# --------------------------

if [ -r "$SCRIPT_DIR/scripts/setup-nvidia.sh" ]; then
    bash "$SCRIPT_DIR/scripts/setup-nvidia.sh"
else
    echo "Warning: scripts/setup-nvidia.sh not found; skipping NVIDIA setup"
fi

# --------------------------
# Base packages
# --------------------------

sudo pacman -S --needed --noconfirm kitty git base-devel linux-headers man-db
sudo mandb
