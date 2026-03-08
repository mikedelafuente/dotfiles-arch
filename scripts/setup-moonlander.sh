#!/bin/bash
# -------------------------
# Setup ZSA Moonlander Keyboard
# -------------------------
# Sets up udev rules for ZSA keyboards (Moonlander, Ergodox EZ, Planck EZ, Voyager)
# and installs Keymapp for firmware flashing and configuration.
# Reference: https://github.com/zsa/wally/wiki/Linux-install

# --------------------------
# Import Common Header
# --------------------------

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

print_tool_setup_start "ZSA Moonlander Keyboard"

# --------------------------
# Setup udev rules for ZSA keyboards
# --------------------------

UDEV_RULES_FILE="/etc/udev/rules.d/50-zsa.rules"

print_line_break "Setting up udev rules for ZSA keyboards"

if [ -f "$UDEV_RULES_FILE" ]; then
    print_info_message "udev rules file already exists at $UDEV_RULES_FILE"
else
    print_info_message "Creating udev rules file at $UDEV_RULES_FILE"

    sudo tee "$UDEV_RULES_FILE" > /dev/null << 'EOF'
# Rules for Oryx web flashing and live training
KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", MODE="0664", GROUP="plugdev"
KERNEL=="hidraw*", ATTRS{idVendor}=="3297", MODE="0664", GROUP="plugdev"

# Legacy rules for live training over webusb (Not needed for firmware v21+)
# Rule for all ZSA keyboards
SUBSYSTEM=="usb", ATTR{idVendor}=="3297", GROUP="plugdev"
# Rule for the Moonlander
SUBSYSTEM=="usb", ATTR{idVendor}=="3297", ATTR{idProduct}=="1969", GROUP="plugdev"
# Rule for the Ergodox EZ
SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="1307", GROUP="plugdev"
# Rule for the Planck EZ
SUBSYSTEM=="usb", ATTR{idVendor}=="feed", ATTR{idProduct}=="6060", GROUP="plugdev"

# Wally Flashing rules for the Ergodox EZ
ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", ENV{ID_MM_DEVICE_IGNORE}="1"
ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789A]?", ENV{MTP_NO_PROBE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789ABCD]?", MODE:="0666"
KERNEL=="ttyACM*", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="04[789B]?", MODE:="0666"

# Keymapp / Wally Flashing rules for the Moonlander and Planck EZ
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE:="0666", SYMLINK+="stm32_dfu"

# Keymapp Flashing rules for the Voyager
SUBSYSTEMS=="usb", ATTRS{idVendor}=="3297", MODE:="0666", SYMLINK+="ignition_dfu"
EOF

    print_success_message "udev rules file created"

    # Reload udev rules
    print_info_message "Reloading udev rules"
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    print_success_message "udev rules reloaded"
fi

# --------------------------
# Setup plugdev group
# --------------------------

print_line_break "Setting up plugdev group"

# Create plugdev group if it doesn't exist
if ! getent group plugdev > /dev/null 2>&1; then
    print_info_message "Creating plugdev group"
    sudo groupadd plugdev
    print_success_message "plugdev group created"
else
    print_info_message "plugdev group already exists"
fi

# Add current user to plugdev group
REAL_USER="${SUDO_USER:-$(whoami)}"
if id -nG "$REAL_USER" | grep -qw plugdev; then
    print_info_message "User $REAL_USER is already in plugdev group"
else
    print_info_message "Adding user $REAL_USER to plugdev group"
    sudo usermod -aG plugdev "$REAL_USER"
    print_success_message "User $REAL_USER added to plugdev group"
    print_warning_message "You may need to log out and back in for group changes to take effect"
fi

# --------------------------
# Install Keymapp (ZSA keyboard configuration tool)
# --------------------------

print_line_break "Installing Keymapp"

if pacman -Q zsa-keymapp-bin &> /dev/null; then
    print_info_message "Keymapp is already installed"
else
    print_info_message "Installing Keymapp from AUR"
    yay -S --needed --noconfirm zsa-keymapp-bin

    if pacman -Q zsa-keymapp-bin &> /dev/null; then
        print_success_message "Keymapp installed successfully"
    else
        print_warning_message "Keymapp installation may have failed"
    fi
fi

print_tool_setup_complete "ZSA Moonlander Keyboard"
