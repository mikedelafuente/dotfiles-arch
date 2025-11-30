#!/bin/bash

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

print_tool_setup_start "Python"

# --------------------------
# Install Python
# --------------------------

# Check if Python is already installed
if command -v python3 &> /dev/null; then
    print_info_message "Python is already installed. Skipping installation."
else
    print_info_message "Installing Python from official Arch repositories"

    # Install Python
    sudo pacman -S --needed --noconfirm python
fi

# Print Python version
print_info_message "Python version: $(python3 --version)"

# Install pip if not already installed
if command -v pip3 &> /dev/null; then
    print_info_message "pip is already installed. Skipping installation."
else
    print_info_message "Installing pip for Python"
    sudo pacman -S --needed --noconfirm python-pip
fi

print_tool_setup_complete "Python"

