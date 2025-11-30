#!/bin/bash

# --------------------------
# Setup Bash Shell for Arch Linux
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

print_tool_setup_start "Bash"

# --------------------------
# Install Bash
# --------------------------

# Install Bash if not already installed (usually pre-installed on Arch)
if ! command -v bash &> /dev/null; then
    print_info_message "Installing Bash via pacman"
    sudo pacman -S --needed --noconfirm bash
else
    print_info_message "Bash is already installed. Skipping installation."
fi

# --------------------------
# Set Bash as Default Shell
# --------------------------

# Set Bash as the default shell
if [ "$SHELL" != "$(which bash)" ]; then
    current_shell=$(which bash)
    print_info_message "Changing default shell ($SHELL) to bash ($current_shell)"
    chsh -s "$current_shell"
else
    print_info_message "Bash is already the default shell. Skipping change."
fi

# --------------------------
# Install Starship Prompt
# --------------------------

# Install Starship prompt for Bash
if ! command -v starship &> /dev/null; then
    print_info_message "Installing Starship prompt for Bash via pacman"
    sudo pacman -S --needed --noconfirm starship
else
    print_info_message "Starship prompt is already installed. Skipping installation."
fi

print_tool_setup_complete "Bash"

