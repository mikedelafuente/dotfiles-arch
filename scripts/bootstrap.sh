#!/bin/bash
# ----------------
# Bootstrap Script for Arch
# ----------------
#
# Determine if we are running with sudo, and if so get the actual user's home directory
if [ "$(whoami)" != "${SUDO_USER:-$(whoami)}" ]; then
    USER_HOME_DIR=$(eval echo ~${SUDO_USER})
else
    USER_HOME_DIR="$HOME"
fi

# Make a bootstrap config folder
BOOTSTRAP_CONFIG_DIR="$USER_HOME_DIR/.config/dotfiles-arch"
mkdir "$BOOTSTRAP_CONFIG_DIR"

# Read in configuration from file if it exists
if [ -r "$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config" ]; then
  # shellcheck source=/dev/null
  source "$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config"
else
  echo "Configuration file not found. Setting based on System User."
  FULL_NAME=""$(getent passwd "$(whoami)" | cut -d ':' -f 5 | cut -d ',' -f 1)""
  DOTNET_CORE_SDK_VERSION="9.0"
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
# Update System Packages
# --------------------------

# Update package list and upgrade installed packages
# Check how recent the last update was

LAST_PACMAN_UPDATE=$(cat "$BOOTSTRAP_CONFIG_DIR/.last_pacman_update" 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
TIME_DIFF=$((CURRENT_TIME - LAST_PACMAN_UPDATE))

# If more than 1 day (86400 seconds) has passed since the last update, perform update
if [ "$TIME_DIFF" -lt 86400 ]; then
    print_info_message "Last Pacman update was less than a day ago. Skipping update."
else
    print_info_message "Last Pacman update was more than a day ago. Performing update."
    sudo pacman -Sy #|| true
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
    sudo pacman -Su
    # Write a file to ~/.last_dnf_upgrade with the current timestamp
    echo "$(date +%s)" > "$BOOTSTRAP_CONFIG_DIR/.last_pacman_upgrade"
fi


# Ensure yay is installed
{
	if ! command -v yay &> /dev/null; then
		echo "Installing yay"
		git clone https://aur.archlinux.org/yay.git
		cd ~/yay
		sudo pacman -S base-devel
		makepkg -si
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
    yay -Syu
fi

# --------------------------
# Run Individual Setup Scripts
# --------------------------

# Install Essential Packages
bash "$DF_SCRIPT_DIR/setup-essentials.sh"

# Set up Git configuration
bash "$DF_SCRIPT_DIR/setup-git.sh" "$FULL_NAME" "$EMAIL_ADDRESS"

# Install Node.js and npm
bash "$DF_SCRIPT_DIR/setup-node.sh"

# Setup GitHub CLI and Copilot CLI
bash "$DF_SCRIPT_DIR/setup-github-cli.sh"

# --------------------------
# Clean Up
# --------------------------

print_line_break "Cleaning up"

ORPHANED_PACKAGES=$(pacman -Qtdq)
if [ -n "$ORPHANED_PACKAGES" ]; then
    # The variable is not empty, meaning there are orphaned packages.
    echo "Found orphaned packages. Removing them now..."
    sudo pacman -Rns $ORPHANED_PACKAGES
else
    # The variable is empty, meaning there are no orphaned packages.
    echo "No orphaned packages found."
fi

print_line_break "Bootstrap completed. Please restart your terminal or log out and log back in."

echo "Shell: $SHELL"

