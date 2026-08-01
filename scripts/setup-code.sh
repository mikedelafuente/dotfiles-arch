#!/bin/bash
# -------------------------
# Setup Code Command - Herdr-based Development Environment Launcher
# -------------------------

# --------------------------
# Import Common Header
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

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

print_tool_setup_start "Code Command (Herdr Development Launcher)"

DEPENDENCIES=(herdr lazygit lazydocker)
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
            herdr)
                bash "$CURRENT_FILE_DIR/setup-herdr.sh"
                ;;
            lazygit)
                sudo pacman -S --needed --noconfirm lazygit
                ;;
            lazydocker)
                yay -S --needed --noconfirm lazydocker
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

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    print_warning_message "~/.local/bin is not in PATH"
    print_info_message "This will be added to PATH when dotfiles are linked"
else
    print_info_message "~/.local/bin is already in PATH"
fi

DOTFILES_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
CODE_SCRIPT="$DOTFILES_DIR/home/.local/bin/code"

if [ -f "$CODE_SCRIPT" ]; then
    chmod +x "$CODE_SCRIPT"
    print_success_message "Made code script executable"
else
    print_error_message "Code script not found at $CODE_SCRIPT"
fi

print_line_break "Setup Complete"
print_info_message "The 'code' command opens a Herdr workspace for a git repo"
print_info_message "Usage: code [directory]"
print_info_message "Cursor IDE is available as: cursor"

print_tool_setup_complete "Code Command"
