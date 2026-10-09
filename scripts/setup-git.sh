#!/bin/bash

# --------------------------
# Setup Git and SSH Keys for rolling Arch / Ubuntu 26.04
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

# --------------------------
# Get Username and Email Arguments
# --------------------------

# See if username and email were passed as arguments
load_bootstrap_config || true
ensure_core_cli git
USERNAME_ARG="${1:-${FULL_NAME:-}}"
EMAIL_ARG="${2:-${EMAIL_ADDRESS:-}}"

# An unrelated identity symlink must not be written through by git config.
if [[ -L "$USER_HOME_DIR/.gitconfig" ]]; then
    case "$(readlink "$USER_HOME_DIR/.gitconfig")" in
        */home/.gitconfig) ;;
        *) print_error_message "Git identity symlink conflict; preserved"; exit 1 ;;
    esac
fi

# Explicit arguments change identity; otherwise preserve machine-local values.
# Migrate legacy identity first so saved bootstrap values cannot overwrite it.
ensure_local_gitconfig
if [[ -z "${1:-}" ]]; then
    USERNAME_ARG="$(git config --file "$USER_HOME_DIR/.gitconfig" --get user.name 2>/dev/null || printf '%s' "$USERNAME_ARG")"
fi
if [[ -z "${2:-}" ]]; then
    EMAIL_ARG="$(git config --file "$USER_HOME_DIR/.gitconfig" --get user.email 2>/dev/null || printf '%s' "$EMAIL_ARG")"
fi

# If not passed as arguments, only prompt when a TTY is available
if [ -z "$USERNAME_ARG" ]; then
    if [ -t 0 ]; then
        read -rp "Enter your full name for git commit history: " USERNAME_ARG
    else
        print_error_message "Full name required (pass as arg 1). Non-interactive run has no TTY."
        exit 1
    fi
fi

if [ -z "$EMAIL_ARG" ]; then
    if [ -t 0 ]; then
        read -rp "Enter your email for git commit history: " EMAIL_ARG
    else
        print_error_message "Email required (pass as arg 2). Non-interactive run has no TTY."
        exit 1
    fi
fi

if [ -z "$USERNAME_ARG" ] || [ -z "$EMAIL_ARG" ]; then
    print_error_message "Both full name and email address are required to set up Git."
    exit 1
fi

# --------------------------
# End check for username and email arguments
# --------------------------

print_tool_setup_start "Git"

# --------------------------
# Ensure Git is Installed
# --------------------------

# Install Git if not already installed
ensure_core_cli openssh
ensure_core_cli lazygit
REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
link_core_cli_config "$REPO_ROOT/config/git/config" "$USER_HOME_DIR/.config/git/config"

# --------------------------
# Configure Git Identity (machine-local)
# --------------------------
# Name/email are per-machine and live in the real (unlinked) ~/.gitconfig.
# Shared settings (editor, defaultBranch, credentials) come from
# config/git/config, linked to ~/.config/git/config by link-dotfiles.

print_info_message "Writing machine-local Git identity"

LOCAL_GITCONFIG="$USER_HOME_DIR/.gitconfig"
git config --file "$LOCAL_GITCONFIG" user.name "$USERNAME_ARG"
git config --file "$LOCAL_GITCONFIG" user.email "$EMAIL_ARG"

print_info_message "Git identity written to $LOCAL_GITCONFIG:"
print_info_message "  Name: $USERNAME_ARG"
print_info_message "  Email: $EMAIL_ARG"
print_info_message "Shared settings (editor, defaultBranch) come from ~/.config/git/config after link-dotfiles"

# --------------------------
# Setup SSH Keys
# --------------------------

print_info_message "Setting up SSH keys for Git"

# Check to see if SSH keys already exist
if [ -f "$USER_HOME_DIR/.ssh/id_ed25519" ]; then
    print_info_message "SSH key already exists. Skipping key generation."
elif [ ! -t 0 ]; then
    print_warning_message "No TTY — skipping SSH key generation."
    print_info_message "Create one later: ssh-keygen -t ed25519 -C \"$EMAIL_ARG\" -f ~/.ssh/id_ed25519"
else
    print_info_message "Generating new SSH key using Ed25519 algorithm"
    
    mkdir -p "$USER_HOME_DIR/.ssh"
    chmod 700 "$USER_HOME_DIR/.ssh"

    echo ""
    read -rsp "SSH key passphrase (Enter for empty — less secure): " SSH_PASS
    echo ""
    read -rsp "Confirm passphrase: " SSH_PASS2
    echo ""
    if [[ "$SSH_PASS" != "$SSH_PASS2" ]]; then
        print_error_message "Passphrases do not match — skipping SSH key generation"
    else
        if [[ -z "$SSH_PASS" ]]; then
            print_warning_message "Creating SSH key with empty passphrase"
        fi
        ssh-keygen -t ed25519 -C "$EMAIL_ARG" -f "$USER_HOME_DIR/.ssh/id_ed25519" -N "$SSH_PASS"
        
        eval "$(ssh-agent -s)"
        ssh-add "$USER_HOME_DIR/.ssh/id_ed25519"
        
        echo ""
        print_info_message "Your public SSH key is:"
        echo ""
        cat "$USER_HOME_DIR/.ssh/id_ed25519.pub"
        echo ""
        print_warning_message "Copy this key to your GitHub account:"
        print_info_message "  https://github.com/settings/keys"
        echo ""
    fi
fi

# --------------------------
# Install lazygit
# --------------------------
print_info_message "Checking for lazygit installation"
lazygit --version

print_tool_setup_complete "Git"
