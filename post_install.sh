#!/bin/bash

# Update pacman so the /etc/pacman.conf has multilib uncommented
#swaylock with sddm and hyprland

# Define the path to pacman.conf
PACMAN_CONF="/etc/pacman.conf"

# Check if the file exists
if [ ! -f "$PACMAN_CONF" ]; then
    echo "Error: $PACMAN_CONF not found."
    exit 1
fi

# Uncomment the [multilib] section and the subsequent Include line
# This sed command finds the line containing "[multilib]", then looks for the next line
# that starts with "#Include" and removes the "#" from both.
sudo sed -i '/^#\[multilib\]/{
    s/^#//
    n
    s/^#//
}' "$PACMAN_CONF"

echo "[multilib] and its Include line have been uncommented in $PACMAN_CONF"

# To check the display Manager
# 

# Update pacman
sudo pacman -Syu

# Install Display Manager
# None needed for Hyperland
sudo pacman -S nvidia-open nvidia-utils nvidia-settings --needed --noconfirm

# Install Desktop Environment (Hyperland + Plasma)
# kitty is a prereq for hyperland
sudo pacman -S kitty --noconfirm

sudo pacman -S hyprland --noconfirm

sudo pacman -S git base-devel linux-headers --needed --noconfirm

sudo pacman -S man-db --noconfirm

sudo mandb
