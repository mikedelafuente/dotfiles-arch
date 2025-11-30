#!/bin/bash

# --------------------------
# Setup Mullvad VPN for Arch Linux
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

print_tool_setup_start "Mullvad VPN"

# --------------------------
# Install Mullvad VPN
# --------------------------

# Install Mullvad VPN if not already installed
if ! command -v mullvad &> /dev/null; then
    print_info_message "Installing Mullvad VPN from AUR via yay"

    # Install the Mullvad VPN package from AUR
    # Using mullvad-vpn-bin for faster installation (pre-compiled binary)
    yay -S --needed --noconfirm mullvad-vpn-bin

    print_info_message "Mullvad VPN installed successfully"
else
    print_info_message "Mullvad VPN is already installed. Skipping installation."
fi

print_tool_setup_complete "Mullvad VPN"

