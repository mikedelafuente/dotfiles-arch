#!/bin/bash
# ----------------
# Bootstrap Script for Arch
# ----------------
# Flags:
#   --yes, -y                 Non-interactive: use saved config / defaults
#   --profile work|personal   Set profile (default: saved or work)
# ----------------

set -euo pipefail

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

ASSUME_YES=false
FORCE_PROFILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --profile=*)
      FORCE_PROFILE="${1#*=}"
      shift
      ;;
    --profile)
      if [ -z "${2:-}" ]; then
        print_error_message "--profile requires an argument (work|personal)"
        exit 1
      fi
      FORCE_PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [options]

Full new-machine bootstrap for dotfiles-arch.
Do not run with sudo.

  --yes, -y                 Non-interactive (saved config / hardware defaults)
  --profile work|personal   Set profile (default: saved or work)
EOF
      exit 0
      ;;
    *)
      print_error_message "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ "$(whoami)" != "${SUDO_USER:-$(whoami)}" ]; then
  print_error_message "Please start this script without sudo."
  exit 1
fi

BOOTSTRAP_CONFIG_DIR="$(bootstrap_config_dir)"
mkdir -p "$BOOTSTRAP_CONFIG_DIR"

if ! load_bootstrap_config; then
  print_info_message "Configuration file not found. Setting based on system user."
  FULL_NAME="$(getent passwd "$(whoami)" | cut -d ':' -f 5 | cut -d ',' -f 1)"
fi

FULL_NAME="${FULL_NAME:-}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"
SETUP_PROFILE="${SETUP_PROFILE:-work}"

if [ -n "$FORCE_PROFILE" ]; then
  if ! SETUP_PROFILE="$(normalize_setup_profile "$FORCE_PROFILE")"; then
    print_error_message "Invalid --profile '$FORCE_PROFILE' (use work or personal)"
    exit 1
  fi
elif ! SETUP_PROFILE="$(normalize_setup_profile "$SETUP_PROFILE")"; then
  SETUP_PROFILE="work"
fi

if [ "$ASSUME_YES" = true ]; then
  if [ -z "$FULL_NAME" ] || [ -z "$EMAIL_ADDRESS" ]; then
    print_error_message "With --yes, FULL_NAME and EMAIL_ADDRESS must already be saved in bootstrap config."
    exit 1
  fi
else
  if [ -z "$FULL_NAME" ]; then
    while [ -z "$FULL_NAME" ]; do
      read -rp "Enter your full name (e.g., John Doe): " FULL_NAME
    done
  else
    read -rp "Enter your full name (e.g., John Doe) [$(fmt_choice "$FULL_NAME")]: " INPUT_FULL_NAME
    if [ -n "${INPUT_FULL_NAME:-}" ]; then
      FULL_NAME="$INPUT_FULL_NAME"
    fi
    while [ -z "$FULL_NAME" ]; do
      read -rp "Full name cannot be empty. Enter your full name: " FULL_NAME
    done
  fi

  if [ -z "$EMAIL_ADDRESS" ]; then
    while [ -z "$EMAIL_ADDRESS" ]; do
      read -rp "Enter your email address (e.g., john.doe@example.com): " EMAIL_ADDRESS
    done
  else
    read -rp "Enter your email address (e.g., john.doe@example.com) [$(fmt_choice "$EMAIL_ADDRESS")]: " INPUT_EMAIL_ADDRESS
    if [ -n "${INPUT_EMAIL_ADDRESS:-}" ]; then
      EMAIL_ADDRESS="$INPUT_EMAIL_ADDRESS"
    fi
    while [ -z "$EMAIL_ADDRESS" ]; do
      read -rp "Email cannot be empty. Enter your email address: " EMAIL_ADDRESS
    done
  fi

  echo ""
  print_info_message "Select setup profile (current: $(fmt_choice "$SETUP_PROFILE")):"
  echo "  1) work      — shared tooling + Zoom + Slack + Chrome"
  echo "  2) personal — shared tooling + Steam + Discord + Firefox + Mullvad"
  read -rp "Profile [1=work, 2=personal] (Enter keeps '$(fmt_choice "$SETUP_PROFILE")'): " PROFILE_INPUT
  if [ -n "${PROFILE_INPUT:-}" ]; then
    if ! SETUP_PROFILE="$(normalize_setup_profile "$PROFILE_INPUT")"; then
      print_error_message "Unknown choice '$PROFILE_INPUT'. Use 1/work or 2/personal."
      exit 1
    fi
  fi
fi

if ! validate_bootstrap_profile; then
  print_error_message "Profile must be 'work' or 'personal' (got: ${SETUP_PROFILE:-})"
  exit 1
fi

resolve_nvidia_preference
resolve_machine_type

if [ "$ASSUME_YES" = false ]; then
  echo ""
  echo "Please confirm the following information:"
  echo "Full Name: $(fmt_choice "$FULL_NAME")"
  echo "Email Address: $(fmt_choice "$EMAIL_ADDRESS")"
  echo "Setup Profile: $(fmt_choice "$SETUP_PROFILE")"
  echo "Install NVIDIA: $(fmt_choice "$INSTALL_NVIDIA")"
  echo "Machine Type: $(fmt_choice "$MACHINE_TYPE")"
  read -rp "Is this information correct? [y/n] (Enter = $(fmt_choice "no")): " CONFIRMATION
  if [[ ! "${CONFIRMATION:-}" =~ ^[Yy]$ ]]; then
    print_error_message "Aborting. Please run the script again to enter the correct information."
    exit 1
  fi
fi

write_bootstrap_config

print_line_break "Starting bootstrap"
print_info_message "Display server: ${XDG_SESSION_TYPE:-unknown}"
print_info_message "User: $(whoami)  Home: $USER_HOME_DIR"
print_info_message "Profile: $SETUP_PROFILE  INSTALL_NVIDIA: $INSTALL_NVIDIA  MACHINE_TYPE: $MACHINE_TYPE"

sudo -v
{
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done
} &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

# --------------------------
# Allow multilib in pacman
# --------------------------

ensure_multilib_enabled || true
PACMAN_CHANGES_MADE=false
if [[ "${MULTILIB_CHANGED:-false}" == "true" ]]; then
  PACMAN_CHANGES_MADE=true
fi

# --------------------------
# Rate-limited guarded system update
# --------------------------

ensure_yay_installed || print_warning_message "yay install failed — AUR steps may fail"

if [ "$PACMAN_CHANGES_MADE" = true ] || system_upgrade_cooldown_expired; then
  if [ "$PACMAN_CHANGES_MADE" = true ]; then
    print_info_message "pacman.conf changed — running guarded system update"
  else
    print_info_message "Package cooldown expired — running guarded system update"
  fi
  export DOTFILES_AUR_ASSUME_YES=true
  if safe_system_upgrade --yes; then
    record_system_upgrade_stamps
  else
    print_warning_message "Guarded system update failed — continuing with setup scripts"
  fi
else
  print_info_message "Last system update was less than a day ago. Skipping upgrade."
fi

# --------------------------
# Run Individual Setup Scripts
# --------------------------

print_info_message "Running bootstrap with profile: $SETUP_PROFILE"

export SETUP_PROFILE FULL_NAME EMAIL_ADDRESS INSTALL_NVIDIA MACHINE_TYPE
export SETUP_CONTINUE_ON_ERROR=true
export DOTFILES_AUR_ASSUME_YES=true
set +e
bash "$DF_SCRIPT_DIR/run-profile-setup.sh"
SETUP_RC=$?
set -e
if [ "$SETUP_RC" -ne 0 ]; then
  print_warning_message "Some setup scripts failed (see above). Continuing with link/cleanup."
fi

bash "$DF_SCRIPT_DIR/link-dotfiles.sh" "$SETUP_PROFILE"
bash "$DF_SCRIPT_DIR/post-link-hooks.sh"

print_line_break "Cleaning up"
remove_orphaned_packages

print_line_break "Bootstrap completed. Please restart your terminal or log out and log back in."
print_info_message "Shell: $SHELL"
