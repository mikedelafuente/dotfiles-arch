#!/bin/bash

# --------------------------
# Setup TablePlus for Arch Linux
# --------------------------
# TablePlus is an application for managing multiple databases. It is installed via yay from
# the AUR (Arch User Repository). This is the recommended method because:
# - Official TablePlus package available in AUR
# - Better integration with system libraries
# - Standard Arch package management via yay
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

print_tool_setup_start "TablePlus"

# Check if TablePlus is already installed
if command -v tableplus &> /dev/null; then
    print_info_message "TablePlus is already installed."
else
    print_info_message "Installing TablePlus from AUR via yay"

    # Install TablePlus from AUR
    yay -S --needed --noconfirm tableplus

    print_info_message "TablePlus installation completed."
fi

print_tool_setup_complete "TablePlus"


