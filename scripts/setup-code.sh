#!/bin/bash
# -------------------------
# Setup Code Command - tmux-based Development Environment Launcher
# -------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Code Command (tmux Development Launcher)"

DEPENDENCIES=(tmux lazygit lazydocker)
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
            lazydocker)
                ensure_yay_pkgs lazydocker
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
    print_warning_message "\$HOME/.local/bin is not in PATH"
    print_info_message "This will be added to PATH when dotfiles are linked"
else
    print_info_message "\$HOME/.local/bin is already in PATH"
fi

DOTFILES_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
CODE_SCRIPT="$DOTFILES_DIR/home/.local/bin/code"

if [ -f "$CODE_SCRIPT" ]; then
    chmod +x "$CODE_SCRIPT"
    print_success_message "Made code script executable"
else
    print_error_message "Code script not found at $CODE_SCRIPT"
fi

# DEFAULT_AGENT drives which agent `code` (no --agent flag) starts by default.
# Runs after profile extras (see run-profile-setup.sh) so Cursor is already
# on PATH if the work profile just installed it.
load_bootstrap_config || true
export ASSUME_YES="${DOTFILES_AUR_ASSUME_YES:-false}"
resolve_default_agent
if [[ -n "$DEFAULT_AGENT" ]]; then
    print_info_message "code's default agent: $DEFAULT_AGENT (override per-run with --agent cursor|claude)"
else
    print_info_message "No agent CLI installed yet — 'code' will open a plain shell pane until one is"
fi
write_bootstrap_config

print_line_break "Setup Complete"
print_info_message "The 'code' command opens a tmux session with Neovim + an agent pane"
print_info_message "Usage: code [directory]"
print_info_message "Agents: code <dir> --agent cursor   (or --agent claude)"
print_info_message "Cursor IDE is available as: cursor"

print_tool_setup_complete "Code Command"
