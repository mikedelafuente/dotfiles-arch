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

print_tool_setup_start "Go (golang)"

# --------------------------
# Install Golang
# --------------------------

# Check if Golang is already installed
if command -v go &> /dev/null; then
    print_info_message "Golang is already installed. Skipping installation."
else
    print_info_message "Installing Go from official Arch repositories"

    # Install Golang
    sudo pacman -S --needed --noconfirm go
fi

# Print Golang version
print_info_message "Golang version: $(go version)"

# Install any extra tooling considered standard for Go development on Arch

# gopls: Language server for Go (provides IDE features)
EXTRA_GO_PACKAGES=(
    "gopls"
)

for package in "${EXTRA_GO_PACKAGES[@]}"; do
    if ! pacman -Qi "$package" &> /dev/null; then
        print_info_message "Installing $package"
        sudo pacman -S --needed --noconfirm "$package"
    else
        print_info_message "$package is already installed. Skipping."
    fi
done

print_tool_setup_complete "Go (golang)"

