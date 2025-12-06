#!/bin/bash
# -------------------------
# Setup Code Command - Development Environment Launcher
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

print_tool_setup_start "Code Command (Development Environment Launcher)"

# --------------------------
# Check Dependencies
# --------------------------

DEPENDENCIES=(tmux lazygit tmuxinator lazydocker mycli)
MISSING_DEPS=()

for dep in "${DEPENDENCIES[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    print_info_message "Installing missing dependencies: ${MISSING_DEPS[*]}"

    for dep in "${MISSING_DEPS[@]}"; do
        case "$dep" in
            tmux)
                sudo pacman -S --needed --noconfirm tmux
                ;;
            lazygit)
                sudo pacman -S --needed --noconfirm lazygit
                ;;
            tmuxinator)
                yay -S --needed --noconfirm tmuxinator
                ;;
            lazydocker)
                yay -S --needed --noconfirm laxydocker
                ;;
            mycli)
                yay -S --needed --noconfirm mycli
                ;;
        esac

        if command -v "$dep" &> /dev/null; then
            print_success_message "$dep installed successfully"
        else
            print_error_message "Failed to install $dep"
        fi
    done
else
    print_info_message "All dependencies are already installed"
fi

# --------------------------
# Ensure ~/.local/bin is in PATH
# --------------------------

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    print_warning_message "~/.local/bin is not in PATH"
    print_info_message "This will be added to PATH when dotfiles are linked"
else
    print_info_message "~/.local/bin is already in PATH"
fi

# --------------------------
# Make code script executable
# --------------------------

DOTFILES_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
CODE_SCRIPT="$DOTFILES_DIR/home/.local/bin/code"

if [ -f "$CODE_SCRIPT" ]; then
    chmod +x "$CODE_SCRIPT"
    print_success_message "Made code script executable"
else
    print_error_message "Code script not found at $CODE_SCRIPT"
    # exit 1
fi

# --------------------------
# Information
# --------------------------

print_line_break "Setup Complete"
print_info_message "The 'code' command will be available after linking dotfiles"
print_info_message "Usage: code [directory]"
print_info_message "Configuration: ~/.config/tmuxinator/code.yml"
print_info_message "See also: ~/.config/code/README.md for customization guide"

print_tool_setup_complete "Code Command"
