#!/bin/bash

# -------------------------
# GitHub CLI and Copilot CLI Setup for Arch Linux
# -------------------------


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


print_tool_setup_start "GitHub CLI and Copilot CLI"

# --------------------------
# Install GitHub CLI (gh)
# --------------------------

if command -v gh &> /dev/null; then
    print_info_message "GitHub CLI (gh) is already installed."
    gh --version
else
    print_action_message "Installing GitHub CLI (gh)..."

    sudo pacman -S --needed --noconfirm github-cli
    
    if command -v gh &> /dev/null; then
        print_success_message "GitHub CLI installed successfully!"
        gh --version
    else
        print_error_message "Failed to install GitHub CLI"
        exit 1
    fi
fi

# --------------------------
# Install GitHub Copilot CLI
# --------------------------

if command -v github-copilot-cli &> /dev/null; then
    print_info_message "GitHub Copilot CLI is already installed."
    github-copilot-cli --version
else
    print_action_message "Installing GitHub Copilot CLI..."
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        print_error_message "npm is not installed. Please run setup-node.sh first."
        exit 1
    fi
    
    # Install GitHub Copilot CLI globally
    sudo npm install -g @githubnext/github-copilot-cli
    
    if command -v github-copilot-cli &> /dev/null; then
        print_success_message "GitHub Copilot CLI installed successfully!"
        github-copilot-cli --version
    else
        print_error_message "Failed to install GitHub Copilot CLI"
        exit 1
    fi
fi

# --------------------------
# Setup Instructions
# --------------------------

print_info_message ""
print_info_message "GitHub CLI and Copilot CLI setup complete!"
print_info_message ""
print_info_message "Next steps:"
print_info_message "  1. Authenticate GitHub CLI:"
print_info_message "     gh auth login"
print_info_message ""
print_info_message "  2. Authenticate GitHub Copilot CLI:"
print_info_message "     github-copilot-cli auth"
print_info_message ""
print_info_message "  3. Use Copilot CLI aliases:"
print_info_message "     ?? <query>    - Get command suggestions"
print_info_message "     git? <query>  - Git-specific help"
print_info_message "     gh? <query>   - GitHub CLI help"
print_info_message ""
print_info_message "Note: GitHub Copilot CLI requires an active GitHub Copilot subscription."

print_tool_setup_complete "GitHub CLI and Copilot CLI"
