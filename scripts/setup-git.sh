#!/bin/bash

# --------------------------
# Setup Git and SSH Keys for Arch Linux
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

# --------------------------
# Get Username and Email Arguments
# --------------------------

# See if username and email were passed as arguments
USERNAME_ARG="$1"
EMAIL_ARG="$2"

# If not passed as arguments, then ask for them
if [ -z "$USERNAME_ARG" ]; then
    read -rp "Enter your full name for git commit history: " USERNAME_ARG
fi

if [ -z "$EMAIL_ARG" ]; then
    read -rp "Enter your email for git commit history: " EMAIL_ARG
fi

if [ -z "$USERNAME_ARG" ] || [ -z "$EMAIL_ARG" ]; then
    print_error_message "Both full name and email address are required to set up Git."
    exit 1
fi

# --------------------------
# End check for username and email arguments
# --------------------------

print_tool_setup_start "Git"

# --------------------------
# Ensure Git is Installed
# --------------------------

# Install Git if not already installed
if ! command -v git &> /dev/null; then
    print_info_message "Git not found. Installing Git via pacman"
    sudo pacman -S --needed --noconfirm git
else
    print_info_message "Git is already installed (version: $(git --version))"
fi

# --------------------------
# Configure Git Settings
# --------------------------

print_info_message "Configuring Git with user information"

git config --global user.name "$USERNAME_ARG"
git config --global user.email "$EMAIL_ARG"
git config --global core.editor "nvim"
git config --global init.defaultBranch main

print_info_message "Git configured successfully:"
print_info_message "  Name: $USERNAME_ARG"
print_info_message "  Email: $EMAIL_ARG"
print_info_message "  Editor: nvim"
print_info_message "  Default Branch: main"

# --------------------------
# Setup SSH Keys
# --------------------------

print_info_message "Setting up SSH keys for Git"

# Check to see if SSH keys already exist
if [ -f "$USER_HOME_DIR/.ssh/id_ed25519" ]; then
    print_info_message "SSH key already exists. Skipping key generation."
else
    print_info_message "Generating new SSH key using Ed25519 algorithm"
    
    # Ensure .ssh directory exists
    mkdir -p "$USER_HOME_DIR/.ssh"
    chmod 700 "$USER_HOME_DIR/.ssh"

    # Create SSH keys for GitHub using Ed25519 without passphrase
    ssh-keygen -t ed25519 -C "$EMAIL_ARG" -f "$USER_HOME_DIR/.ssh/id_ed25519" -N ""
    
    # Add SSH key to ssh-agent
    eval "$(ssh-agent -s)"
    ssh-add "$USER_HOME_DIR/.ssh/id_ed25519"
    
    # Display the public key for GitHub
    echo ""
    print_info_message "Your public SSH key is:"
    echo ""
    cat "$USER_HOME_DIR/.ssh/id_ed25519.pub"
    echo ""
    print_warning_message "Copy this key to your GitHub account:"
    print_info_message "  https://github.com/settings/keys"
    echo ""
fi

# --------------------------
# Install lazygit
# --------------------------
print_info_message "Checking for lazygit installation"
if ! command -v lazygit &> /dev/null; then
    print_info_message "lazygit not found. Installing lazygit via pacman"
    sudo pacman -S --needed --noconfirm lazygit
else
    print_info_message "lazygit is already installed (version: $(lazygit --version))"
fi

print_tool_setup_complete "Git"
