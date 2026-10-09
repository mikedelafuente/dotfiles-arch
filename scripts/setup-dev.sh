#!/bin/bash
# -------------------------
# Setup dev Command - Zed-first Development Environment Launcher
# -------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "dev Command (Development Launcher)"

REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
editor_config_allowed "$REPO_ROOT/home/.tmux.conf" "$USER_HOME_DIR/.tmux.conf" || {
    print_error_message "tmux config conflict; preserved"
    exit 1
}
ensure_core_cli lazygit || exit 1
# Prerequisites for the verified Ubuntu lazydocker release exception.
ensure_core_cli curl || exit 1
ensure_core_cli jq || exit 1
case "$WORKSTATION_DISTRO" in
    arch) ensure_native_pkgs python tar gzip ca-certificates ;;
    ubuntu) ensure_native_pkgs python3 tar gzip ca-certificates ;;
esac
ensure_editor_tool tmux || exit 1
ensure_editor_tool lazydocker || exit 1
link_editor_config "$REPO_ROOT/home/.tmux.conf" "$USER_HOME_DIR/.tmux.conf" || exit 1

if [[ ":$PATH:" != *":$USER_HOME_DIR/.local/bin:"* ]]; then
    print_warning_message "$USER_HOME_DIR/.local/bin is not in PATH; source the shared shell configuration before using dev"
else
    print_info_message "$USER_HOME_DIR/.local/bin is already in PATH"
fi

DOTFILES_DIR="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
DEV_SCRIPT="$DOTFILES_DIR/home/.local/bin/dev"

if [ -f "$DEV_SCRIPT" ]; then
    chmod +x "$DEV_SCRIPT"
    print_success_message "Made dev script executable"
else
    print_error_message "dev script not found at $DEV_SCRIPT"
    exit 1
fi

# DEFAULT_HARNESS drives which agent harness `dev --tmux` starts in its agent
# pane, and which one zed-agent-init execs in a Zed Terminal Thread. Runs after
# profile extras (see run-profile-setup.sh) so any profile-installed tools are
# already on PATH.
load_bootstrap_config || true
export ASSUME_YES="${DOTFILES_AUR_ASSUME_YES:-false}"
resolve_default_harness
HARNESS_LIST="$(IFS='|'; echo "${KNOWN_HARNESSES[*]}")"
if [[ -n "$DEFAULT_HARNESS" ]]; then
    print_info_message "Default agent harness: $DEFAULT_HARNESS (override per-run with: dev --agent $HARNESS_LIST)"
else
    print_info_message "No agent harness CLI installed yet — 'dev --tmux' will open a plain shell pane until one is"
fi
write_bootstrap_config

print_line_break "Setup Complete"
print_info_message "The 'dev' command opens a project in Zed"
print_info_message "Usage: dev [directory]"
print_info_message "tmux + Neovim session instead: dev --tmux [directory]"
print_info_message "Agents: dev --tmux <dir> --agent <harness>   (one of: $HARNESS_LIST)"

print_tool_setup_complete "dev Command"
