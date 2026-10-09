#!/bin/bash
# -----------------------------------------------------------------------------
# sync.sh — Bring this machine in line with the current dotfiles-arch repo
#
# Use on an already-installed system after pulling large config changes, or on
# any other machine that has drifted from the desired setup.
#
#   cd ~/repos/dotfiles-arch   # or wherever this repo lives
#   git pull
#   bash scripts/sync.sh
#
# Always runs a guarded native upgrade and selected app updaters.
#
# Flags:
#   --profile LIST            One or more profiles: work, personal, devcontainer
#   --prompt                  Re-ask profiles / NVIDIA / machine type even when saved
#   --cleanup                 Preview native orphans and Arch obsolete packages
#   --remove-obsolete         Arch-only obsolete removal; terminal + type remove
#   --skip-bootstrap          Skip setup-*.sh runs (still upgrades + links)
#   --yes                     Non-interactive; requires --profile if none saved
# -----------------------------------------------------------------------------

set -euo pipefail

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

FORCE_PROFILE=""
DO_CLEANUP=false
REMOVE_OBSOLETE=false
SKIP_BOOTSTRAP=false
ASSUME_YES=false
FORCE_PROMPT=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Bring this machine in line with the current dotfiles-arch repo.
Rolling Arch / installed Ubuntu 26.04 GNOME on x86_64/amd64.
Always runs guarded native updates and selected app updaters.

Options:
  --profile LIST            One or more profiles (comma/space): work, personal, devcontainer
                            Required with --yes if none is saved. Example: work,devcontainer
  --prompt                  Re-ask profiles / NVIDIA / machine type even when saved
  --cleanup                 Preview native orphans and Arch obsolete packages
  --remove-obsolete         Arch only: preview recursive obsolete removal, then
                            require a terminal and typing remove (--yes is insufficient)
  --skip-bootstrap          Skip setup-*.sh runs (still upgrades + links)
  --yes, -y                 Non-interactive where safe (also AUR --noconfirm after scan)
  -h, --help                Show this help

Saved profiles/NVIDIA/machine type are kept silently unless unset, --profile, or --prompt.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile=*|--profiles=*)
      FORCE_PROFILE="${1#*=}"
      shift
      ;;
    --profile|--profiles)
      if [ -z "${2:-}" ]; then
        print_error_message "--profile requires an argument (e.g. work,devcontainer)"
        exit 1
      fi
      FORCE_PROFILE="$2"
      shift 2
      ;;
    --prompt)
      FORCE_PROMPT=true
      shift
      ;;
    --cleanup)
      DO_CLEANUP=true
      shift
      ;;
    --remove-obsolete)
      REMOVE_OBSOLETE=true
      DO_CLEANUP=true
      shift
      ;;
    --skip-bootstrap)
      SKIP_BOOTSTRAP=true
      shift
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print_error_message "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$REMOVE_OBSOLETE" == true && "$WORKSTATION_DISTRO" != arch ]]; then
  print_error_message "--remove-obsolete is Arch-only; use dfa-remove-orphans --remove for native cleanup"
  exit 1
fi

# --------------------------
# Resolve profiles (multi-select)
# --------------------------

mkdir -p "$(bootstrap_config_dir)"

SAVED_PROFILES=""
SAVED_NVIDIA=""
SAVED_MACHINE_TYPE=""
if load_bootstrap_config; then
  SAVED_PROFILES="${SETUP_PROFILES:-}"
  SAVED_NVIDIA="${INSTALL_NVIDIA:-}"
  SAVED_MACHINE_TYPE="${MACHINE_TYPE:-}"
fi

SETUP_PROFILES=""

if [ -n "$FORCE_PROFILE" ]; then
  if ! SETUP_PROFILES="$(normalize_setup_profiles "$FORCE_PROFILE")"; then
    print_error_message "Invalid --profile '$FORCE_PROFILE' (use work, personal, and/or devcontainer)"
    exit 1
  fi
elif [ -n "$SAVED_PROFILES" ]; then
  if ! SETUP_PROFILES="$(normalize_setup_profiles "$SAVED_PROFILES")"; then
    print_warning_message "Saved profiles '$SAVED_PROFILES' are invalid; you'll need to choose again"
    SETUP_PROFILES=""
  fi
fi

if [ -z "$SETUP_PROFILES" ]; then
  if [ "$ASSUME_YES" = true ]; then
    print_error_message "No profiles set. Pass --profile work,devcontainer (required with --yes)."
    exit 1
  fi

  echo ""
  print_info_message "No setup profiles are configured for this machine yet."
  print_setup_profile_menu
  while true; do
    read -rp "Profiles: " PROFILE_INPUT
    if SETUP_PROFILES="$(normalize_setup_profiles "${PROFILE_INPUT:-}")"; then
      break
    fi
    print_warning_message "Please choose valid numbers/names (e.g. 1,3 or work,devcontainer)"
  done
elif [ "$ASSUME_YES" = false ] && [ "$FORCE_PROMPT" = true ]; then
  echo ""
  print_info_message "Current saved profiles: $(fmt_choice "$(format_setup_profiles "$SETUP_PROFILES")")"
  print_setup_profile_menu
  read -rp "Profiles (Enter keeps '$(fmt_choice "$(format_setup_profiles "$SETUP_PROFILES")")'): " PROFILE_INPUT
  if [ -n "${PROFILE_INPUT:-}" ]; then
    if ! SETUP_PROFILES="$(normalize_setup_profiles "$PROFILE_INPUT")"; then
      print_error_message "Unknown choice '$PROFILE_INPUT'"
      exit 1
    fi
  fi
else
  print_info_message "Using profiles: $(fmt_choice "$(format_setup_profiles "$SETUP_PROFILES")")"
fi

# shellcheck disable=SC2034 # exported by run_profile_setup_scripts (fn-lib.sh)
SETUP_PROFILE="$(primary_setup_profile)"
if ! validate_bootstrap_profile; then
  print_error_message "Profiles must be a non-empty subset of work|personal|devcontainer (got: ${SETUP_PROFILES:-})"
  exit 1
fi

INSTALL_NVIDIA="${SAVED_NVIDIA:-}"
if [ -z "$INSTALL_NVIDIA" ] || [ "$FORCE_PROMPT" = true ]; then
  resolve_nvidia_preference
else
  print_info_message "Using INSTALL_NVIDIA: $(fmt_choice "$INSTALL_NVIDIA")"
fi

MACHINE_TYPE="${SAVED_MACHINE_TYPE:-}"
if [ -z "$MACHINE_TYPE" ] || [ "$FORCE_PROMPT" = true ]; then
  resolve_machine_type
else
  print_info_message "Using MACHINE_TYPE: $(fmt_choice "$MACHINE_TYPE")"
fi

FULL_NAME="${FULL_NAME:-}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"
write_bootstrap_config

SYNC_STATUS=0
print_line_break "Syncing machine to dotfiles-arch ($(format_setup_profiles))"
print_info_message "Repo: $REPO_ROOT"

# --------------------------
# Ensure we're up to date
# --------------------------

# Source acquisition is explicit and checked before package/setup mutations.
if [[ -e "$REPO_ROOT/.git" ]]; then
  python3 "$DF_SCRIPT_DIR/deployment.py" update --source "$REPO_ROOT" || exit 1
  exec bash "$(readlink -f "$USER_HOME_DIR/.local/share/workstation/config")/scripts/sync.sh" "$@"
fi

# --------------------------
# Guarded system upgrade (always)
# --------------------------

if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
  sudo -v
fi

start_sudo_keepalive

if [[ "$WORKSTATION_DISTRO" == arch ]]; then
  ensure_yay_installed || {
    print_error_message "yay install failed — required AUR setup may fail"
    SYNC_STATUS=1
  }
fi

set +e
if [ "$ASSUME_YES" = true ]; then
  safe_system_upgrade --yes
else
  safe_system_upgrade
fi
UPGRADE_STATUS=$?
set -e
if [ "$UPGRADE_STATUS" -eq 0 ]; then
  if [[ "$SYNC_STATUS" -eq 0 ]]; then
    record_system_upgrade_stamps || SYNC_STATUS=1
  fi
else
  SYNC_STATUS=1
  print_warning_message "Guarded system update failed — continuing with link/setup/cleanup."
fi

# --------------------------
# Re-apply setup scripts (idempotent)
# --------------------------

if [ "$SKIP_BOOTSTRAP" = false ]; then
  print_line_break "Running setup scripts (safe to re-run)"
  run_profile_setup_scripts "$ASSUME_YES" || SYNC_STATUS=1
else
  print_info_message "Skipping setup scripts (--skip-bootstrap)"
fi

# --------------------------
# Relink dotfiles
# --------------------------

print_line_break "Linking dotfiles"
bash "$DF_SCRIPT_DIR/link-dotfiles.sh" "$(format_setup_profiles)" || SYNC_STATUS=1
bash "$DF_SCRIPT_DIR/post-link-hooks.sh" || SYNC_STATUS=1

# --------------------------
# Optional cleanup of obsolete tooling
# --------------------------

OBSOLETE_PKG_CANDIDATES=(
  herdr-bin
  tmuxinator
  ghostty
  alacritty
  hyprland
  hyprpaper
  hyprlock
  hypridle
  hyprshot
  waybar
  swaync
)

# Populate OBSOLETE_PKGS_INSTALLED with candidate packages that are installed.
collect_obsolete_pkgs() {
  OBSOLETE_PKGS_INSTALLED=()
  local pkg
  for pkg in "${OBSOLETE_PKG_CANDIDATES[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
      OBSOLETE_PKGS_INSTALLED+=("$pkg")
    fi
  done
}

cleanup_obsolete() {
  local plan reply="" interactive=false
  # Legacy package names apply only to Arch. Preserve npm packages and user
  # config directories: they have no repository-owned removal contract.
  if [[ "$WORKSTATION_DISTRO" == arch ]]; then
    collect_obsolete_pkgs
    if ((${#OBSOLETE_PKGS_INSTALLED[@]})); then
      plan="$(pacman -Rns --print --print-format '%n %v' "${OBSOLETE_PKGS_INSTALLED[@]}")" || return $?
      print_action_message "Arch obsolete removal plan (including dependencies):"
      printf '%s\n' "$plan"
      if [[ "$REMOVE_OBSOLETE" == true ]]; then
        [[ ! -t 0 || ! -t 1 ]] || interactive=true
        if [[ "$interactive" == true ]]; then
          read -r -p "Type remove to authorize obsolete package removal: " reply || return 1
        fi
        orphan_removal_allowed "$REMOVE_OBSOLETE" "$interactive" "$reply" || {
          print_error_message "Obsolete removal not authorized: terminal + type remove required"
          return 1
        }
        sudo pacman -Rns "${OBSOLETE_PKGS_INSTALLED[@]}" || return $?
      else
        print_info_message "Preview only. Use --remove-obsolete in a terminal for obsolete package removal."
      fi
    else
      print_info_message "No obsolete Arch packages installed"
    fi
  fi
  remove_orphaned_packages || return $?
}

if [[ "$DO_CLEANUP" == true ]]; then
  cleanup_obsolete || SYNC_STATUS=1
else
  print_info_message "Cleanup skipped. --cleanup previews; dfa-remove-orphans --remove separately confirms native removal."
fi

if [[ "$SYNC_STATUS" -ne 0 ]]; then
  print_error_message "Sync finished with failures (see above)"
  exit 1
fi
print_line_break "Sync complete"
print_success_message "Profiles: $(format_setup_profiles)"
print_info_message "Commands on PATH (via ~/.local/bin): dfa-sync-dotfiles, dfa-update-system"
print_info_message "Restart the terminal (or log out/in) so PATH, Kitty defaults, and shell aliases refresh."
print_info_message "If GNOME shortcuts/tray/fonts look wrong: log out and back in so extensions reload."
print_info_message "Neovim: open nvim once and run :Lazy sync / :TSUpdate if plugins look stale."
print_info_message "On other machines: clone/pull this repo, then run:  dfa-sync-dotfiles   # or: bash scripts/sync.sh"
