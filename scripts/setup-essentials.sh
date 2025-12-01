#!/bin/bash
# -------------------------
# Setup Essential Packages
# -------------------------

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

# --------------------------
# Install Essential Packages
# --------------------------

print_tool_setup_start "Essential Packages"

# make sure to call these out these installed tools in the .bashrc aliases and functions as well
ESSENTIAL_PACKAGES=(git curl wget xsel fzf ripgrep fd bat htop ncdu tree jq tmux net-tools btop duf stow shellcheck github-cli tldr fastfetch zoxide linux-firmware-intel)
print_line_break "Installing essential packages"

# Batch check which packages need to be installed
PACKAGES_TO_INSTALL=()
for package in "${ESSENTIAL_PACKAGES[@]}"; do
    if ! pacman -Q "$package" &> /dev/null; then
        PACKAGES_TO_INSTALL+=("$package")
    else
        print_info_message "$package is already installed."
    fi
done

# Batch install all missing packages in one command
if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    print_info_message "Installing ${#PACKAGES_TO_INSTALL[@]} package(s): ${PACKAGES_TO_INSTALL[*]}"
    sudo pacman -S --needed --noconfirm "${PACKAGES_TO_INSTALL[@]}"

    # Verify installations
    for package in "${PACKAGES_TO_INSTALL[@]}"; do
        if pacman -Q "$package" &> /dev/null; then
            print_info_message "$package installed successfully"
        else
            print_warning_message "$package installation may have failed"
        fi
    done
else
    print_info_message "All essential packages are already installed."
fi

# Post-installation hooks for packages that need special initialization
if pacman -Q zoxide &> /dev/null && command -v zoxide &> /dev/null; then
    print_info_message "Initializing zoxide for current session"
    eval "$(zoxide init bash)"
fi

print_tool_setup_complete "Essential Packages"
