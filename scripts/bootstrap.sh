#!/bin/bash
# ----------------
# Bootstrap Script for Arch
# ----------------
#
# Determine if we are running with sudo, and if so get the actual user's home directory
if [ "$(whoami)" != "${SUDO_USER:-$(whoami)}" ]; then
    USER_HOME_DIR=$(eval echo "~${SUDO_USER}")
else
    USER_HOME_DIR="$HOME"
fi

# Make a bootstrap config folder
BOOTSTRAP_CONFIG_DIR="$USER_HOME_DIR/.config/dotfiles-arch"
mkdir -p "$BOOTSTRAP_CONFIG_DIR"

# Read in configuration from file if it exists
if [ -r "$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config" ]; then
  # shellcheck source=/dev/null
  source "$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config"
else
  echo "Configuration file not found. Setting based on System User."
  FULL_NAME=""$(getent passwd "$(whoami)" | cut -d ':' -f 5 | cut -d ',' -f 1)""
fi

# Prompt for full name
if [ -z "$FULL_NAME" ]; then
  read -rp "Enter your full name (e.g., John Doe): " FULL_NAME
else
  read -rp "Enter your full name (e.g., John Doe) [$FULL_NAME]: " INPUT_FULL_NAME
  if [ -n "$INPUT_FULL_NAME" ]; then
    FULL_NAME="$INPUT_FULL_NAME"
  fi
fi

# Prompt for email address
if [ -z "$EMAIL_ADDRESS" ]; then
  read -rp "Enter your email address (e.g., john.doe@example.com): " EMAIL_ADDRESS
else
  read -rp "Enter your email address (e.g., john.doe@example.com) [$EMAIL_ADDRESS]: " INPUT_EMAIL_ADDRESS
  if [ -n "$INPUT_EMAIL_ADDRESS" ]; then
    EMAIL_ADDRESS="$INPUT_EMAIL_ADDRESS"
  fi
fi


# Validate the variables with the user
echo "Please confirm the following information:"
echo "Full Name: $FULL_NAME"
echo "Email Address: $EMAIL_ADDRESS"

read -rp "Is this information correct? (y/n): " CONFIRMATION
if [[ ! "$CONFIRMATION" =~ ^[Yy]$ ]]; then
  echo "Aborting. Please run the script again to enter the correct information."
  exit 1
fi

# Write the configuration file
{
  echo "# Configuration file for dotfiles bootstrap script"
  echo "FULL_NAME=\"$FULL_NAME\""
  echo "EMAIL_ADDRESS=\"$EMAIL_ADDRESS\""
} > "$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config"

# --------------------------
# Start of Bootstrap Script
# --------------------------

echo "Starting bootstrap process... pwd is $(pwd)"
echo "Display server protocol: $XDG_SESSION_TYPE"
echo "Current user: $(whoami)"
echo "Home directory: $HOME"
echo "Real user: ${SUDO_USER:-$(whoami)}"
echo "Home directory of real user: $(eval echo ~${SUDO_USER:-$(whoami)})" 
echo "Shell: $SHELL"
echo "Script directory: $(dirname -- "${BASH_SOURCE[0]}")"
echo "----------------------------------------"

if [ "$(whoami)" != "${SUDO_USER:-$(whoami)}" ]; then
    echo "Please start this script without sudo."
    exit 1
fi

# Run a sudo command early to prompt for the password
sudo -v

# Keep sudo alive in the background for the duration of the script
# This prevents multiple password prompts during a long bootstrap process
{
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" 2>/dev/null || exit
    done
} &
SUDO_KEEPALIVE_PID=$!

# Ensure we kill the keepalive process when the script exits
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# --------------------------
# Import Common Header
# --------------------------

# Add header file
CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# Source header (uses SCRIPT_DIR and loads lib.sh)
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

# Set the script directory variable
DF_SCRIPT_DIR="$CURRENT_FILE_DIR"

# --------------------------
# Allow multilib in pacman
# --------------------------

PACMAN_CONF="/etc/pacman.conf"
PACMAN_CHANGES_MADE=false

if [ ! -f "$PACMAN_CONF" ]; then
    echo "Error: $PACMAN_CONF not found."
    exit 1
fi

if grep -q "^\[multilib\]" "$PACMAN_CONF"; then
    echo "[multilib] is already enabled in $PACMAN_CONF"
else
    if grep -q "^#\[multilib\]" "$PACMAN_CONF"; then
        sudo sed -i '/^#\[multilib\]/{ s/^#//; n; s/^#//; }' "$PACMAN_CONF"
        echo "[multilib] and its Include line have been uncommented in $PACMAN_CONF"
        CHANGES_MADE=true
    else
        echo "[multilib] section not found in $PACMAN_CONF"
    fi
fi

if [ "$PACMAN_CHANGES_MADE" = true ]; then
    echo "Running pacman -Syu to update package database..."
    sudo pacman -Syu --noconfirm
fi

# To check the display Manager
# 

# --------------------------
# Update System Packages
# --------------------------

# Update package list and upgrade installed packages
# Check how recent the last update was

LAST_PACMAN_UPDATE=$(cat "$BOOTSTRAP_CONFIG_DIR/.last_pacman_update" 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_PACMAN_UPDATE))

# If more than 1 day (86400 seconds) has passed since the last update, perform update
if [ "$TIME_DIFF" -lt 86400 ] && [ "$PACMAN_CHANGES_MADE" = false ]; then
    print_info_message "Last Pacman update was less than a day ago. Skipping update."
else
    print_info_message "Last Pacman update was more than a day ago or changes to pacman.conf was made. Performing update."
    sudo pacman -Sy --noconfirm #|| true
    # Write a file to ~/.last_pacman_update with the current timestamp
    echo "$(date +%s)" > "$BOOTSTRAP_CONFIG_DIR/.last_pacman_update"
fi

LAST_PACMAN_UPGRADE=$(cat "$BOOTSTRAP_CONFIG_DIR/.last_pacman_upgrade" 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_PACMAN_UPGRADE))

# If more than 1 day (86400 seconds) has passed since the last upgrade, perform upgrade
if [ "$TIME_DIFF" -lt 86400 ]; then
    print_info_message "Last Pacman upgrade was less than a day ago. Skipping upgrade."
else
    print_info_message "Last Pacman upgrade was more than a day ago. Performing upgrade."
    sudo pacman -Su --noconfirm
    # Write a file to ~/.last_pacman_upgrade with the current timestamp
    echo "$(date +%s)" > "$BOOTSTRAP_CONFIG_DIR/.last_pacman_upgrade"
fi


# Ensure yay is installed
{
	if ! command -v yay &> /dev/null; then
		echo "Installing yay"
		cd "$USER_HOME_DIR" || exit 1
		git clone https://aur.archlinux.org/yay.git
		cd yay || exit 1
		sudo pacman -S --needed --noconfirm base-devel
		makepkg -si --noconfirm
		cd "$USER_HOME_DIR" || exit 1
		rm -rf yay
	fi
}

# Update Flatpak apps if they have not been updated in the last day
LAST_YAY_UPDATE=$(cat "$BOOTSTRAP_CONFIG_DIR/.last_yay_update" 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_YAY_UPDATE)) 

if [ "$TIME_DIFF" -lt 86400 ]; then
    print_info_message "Last Yay update was less than a day ago. Skipping update."
else
    print_info_message "Last Yay update was more than a day ago. Performing update."
    # Write a file to ~/.last_flatpak_update with the current timestamp
    echo "$(date +%s)" > "$BOOTSTRAP_CONFIG_DIR/.last_yay_update"
    yay -Syu --noconfirm
fi

# --------------------------
# Run Individual Setup Scripts
# --------------------------

# Install Essential Packages
bash "$DF_SCRIPT_DIR/setup-essentials.sh"

# Set up Git configuration
bash "$DF_SCRIPT_DIR/setup-git.sh" "$FULL_NAME" "$EMAIL_ADDRESS"

# Setup GitHub CLI and Copilot CLI
bash "$DF_SCRIPT_DIR/setup-github-cli.sh"

# --------------------------
# Run Individual Setup Scripts
# --------------------------

# Install Node.js and npm (needed by multiple tools)
bash "$DF_SCRIPT_DIR/setup-node.sh"

# Setup Python
bash "$DF_SCRIPT_DIR/setup-python.sh"

# Setup Fonts
bash "$DF_SCRIPT_DIR/setup-fonts.sh"

# Setup Bash
bash "$DF_SCRIPT_DIR/setup-bash.sh"

# Before setting up Alacritty, ensure Rust is installed
bash "$DF_SCRIPT_DIR/setup-rust.sh"

# Setup Go (Golang)
bash "$DF_SCRIPT_DIR/setup-golang.sh"

# Setup Kitty with Catpuccin theme
bash "$DF_SCRIPT_DIR/setup-kitty.sh"

# Setup TablePlus for database management
bash "$DF_SCRIPT_DIR/setup-tableplus.sh"

# Setup Neovim and Lazyvim - This needs to run after python setup
bash "$DF_SCRIPT_DIR/setup-neovim.sh"

# Setup Mullvad VPN
bash "$DF_SCRIPT_DIR/setup-mullvad.sh"

# Run the setup-docker.sh script to set up Docker
bash "$DF_SCRIPT_DIR/setup-docker.sh"

# Setup Minikube (Kubernetes cluster manager)
bash "$DF_SCRIPT_DIR/setup-minikube.sh"

# Install Claude Code CLI
bash "$DF_SCRIPT_DIR/setup-claude.sh"

# Setup Code Command (development environment launcher)
bash "$DF_SCRIPT_DIR/setup-code.sh"

# Install PHP
bash "$DF_SCRIPT_DIR/setup-php.sh"

# Install Ruby on Rails
bash "$DF_SCRIPT_DIR/setup-ruby.sh"

# Install Postman
bash "$DF_SCRIPT_DIR/setup-postman.sh"

# Install Steam
bash "$DF_SCRIPT_DIR/setup-steam.sh"

# Install Discord
bash "$DF_SCRIPT_DIR/setup-discord.sh"

# Install Spotify
bash "$DF_SCRIPT_DIR/setup-spotify.sh"

# Install Obsidian
bash "$DF_SCRIPT_DIR/setup-obsidian.sh"

# Install Zoom
bash "$DF_SCRIPT_DIR/setup-zoom.sh"

# Setup GNOME with Catppuccin theme (if GNOME is installed)
if pacman -Q gnome-shell &> /dev/null; then
    print_info_message "GNOME is installed. Running GNOME setup..."
    bash "$DF_SCRIPT_DIR/setup-gnome.sh"
else
    print_info_message "GNOME is not installed. Skipping GNOME setup."
fi

# Setup Hyprland UI (if Hyprland is installed)
if pacman -Q hyprland &> /dev/null; then
    print_info_message "Hyprland is installed. Running Hyprland setup..."
    bash "$DF_SCRIPT_DIR/setup-hyprland.sh"
else
    print_info_message "Hyprland is not installed. Skipping Hyprland setup."
fi

# Link dotfiles
bash "$DF_SCRIPT_DIR/link-dotfiles.sh"

# --------------------------
# Clean Up
# --------------------------

print_line_break "Cleaning up"

ORPHANED_PACKAGES=$(pacman -Qtdq)
if [ -n "$ORPHANED_PACKAGES" ]; then
    # The variable is not empty, meaning there are orphaned packages.
    echo "Found orphaned packages. Removing them now..."
    sudo pacman -Rns --noconfirm $ORPHANED_PACKAGES
else
    # The variable is empty, meaning there are no orphaned packages.
    echo "No orphaned packages found."
fi

print_line_break "Bootstrap completed. Please restart your terminal or log out and log back in."

echo "Shell: $SHELL"

