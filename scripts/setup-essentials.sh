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

for package in "${ESSENTIAL_PACKAGES[@]}"; do
    # Use rpm -q to check if package is actually installed (more reliable than dnf list installed)
    if ! pacman -Q "$package" &> /dev/null; then
        print_info_message "Installing $package"
        sudo pacman -S "$package" --noconfirm
        
        # Verify installation succeeded
        if pacman -Q "$package" &> /dev/null; then
            print_info_message "$package installed successfully"
            
            # Post-installation hooks for packages that need special initialization
            case "$package" in
                zoxide)
                    print_info_message "Initializing zoxide for current session"
                    if command -v zoxide &> /dev/null; then
                        eval "$(zoxide init bash)"
                    fi
                    ;;
                # Add more special cases here as needed
                # example)
                #     print_info_message "Running special setup for example"
                #     special_command_here
                #     ;;
            esac
        else
            print_info_message "Warning: $package installation may have failed"
        fi
    else
        print_info_message "$package is already installed. Skipping installation."
    fi
done

print_tool_setup_complete "Essential Packages"
