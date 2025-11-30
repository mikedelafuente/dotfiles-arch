#!/bin/bash

# --------------------------
# Setup NVM and Node.js for Arch
# --------------------------
# This script installs NVM (Node Version Manager) which is the recommended
# way to manage Node.js versions on Arch. NVM allows easy version switching
# and is maintained through its own update mechanism.
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

print_tool_setup_start "NVM and Node.js"

# --------------------------
# Install NVM (Node Version Manager)
# --------------------------

# NVM is the recommended way to install Node.js on Arch because:
# 1. Allows multiple Node.js versions simultaneously
# 2. Per-user installation (no sudo required for package installs)
# 3. Easy version switching with 'nvm use'
# 4. Updated via 'nvm install <version>' or reinstalling the script

# Check if NVM is already installed
if [ ! -d "$USER_HOME_DIR/.nvm" ]; then
    print_info_message "NVM is not installed. Proceeding with installation."
    
    # Ensure curl is installed (required for NVM installation)
    if ! command -v curl &> /dev/null; then
        print_info_message "Installing curl (required for NVM installation)"
        sudo pacman -S --needed --noconfirm curl
    fi
    
    # Download and run the NVM installation script
    print_info_message "Downloading and installing NVM v0.40.3"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    
    print_info_message "NVM installed successfully"
else
    print_info_message "NVM is already installed at $USER_HOME_DIR/.nvm"
fi

# --------------------------
# Load NVM and Install Node.js LTS
# --------------------------

# Load NVM into the current shell
export NVM_DIR="$USER_HOME_DIR/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Check if NVM is now available
if command -v nvm &> /dev/null; then
    print_info_message "Installing Node.js LTS version via NVM"
    nvm install --lts
    # nvm use --lts
    nvm alias default 'lts/*'
    
    print_action_message "Run the following command to set Node.js LTS as default:"
    print_action_message "  nvm use --lts"

    print_info_message "Node.js version: $(node --version)"
    print_info_message "npm version: $(npm --version)"
    print_info_message "NVM version: $(nvm --version)"
    echo ""
    print_info_message "To use NVM in new terminals, restart your terminal or run:"
    print_info_message "  source ~/.bashrc"
else
    print_warning_message "NVM not available in current shell."
    print_info_message "Please restart your terminal and run: nvm install --lts"
fi

print_tool_setup_complete "NVM and Node.js"
