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
# Always runs a guarded pacman + yay upgrade (same path as update-system.sh).
#
# Flags:
#   --profile LIST            One or more profiles: work, personal, devcontainer
#   --prompt                  Re-ask profiles / NVIDIA / machine type even when saved
#   --cleanup                 Remove obsolete packages (herdr, ghostty, etc.)
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
SKIP_BOOTSTRAP=false
ASSUME_YES=false
FORCE_PROMPT=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Bring this machine in line with the current dotfiles-arch repo.
Always runs a guarded system upgrade (pacman + yay with AUR IoC scan).

Options:
  --profile LIST            One or more profiles (comma/space): work, personal, devcontainer
                            Required with --yes if none is saved. Example: work,devcontainer
  --prompt                  Re-ask profiles / NVIDIA / machine type even when saved
  --cleanup                 Remove obsolete packages (herdr, ghostty, etc.)
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

print_line_break "Syncing machine to dotfiles-arch ($(format_setup_profiles))"
print_info_message "Repo: $REPO_ROOT"

# --------------------------
# Ensure we're up to date
# --------------------------

if [ -d "$REPO_ROOT/.git" ]; then
  print_info_message "Fetching latest from git (fast-forward only)..."
  if git -C "$REPO_ROOT" pull --ff-only; then
    print_success_message "Repo updated"
  else
    print_warning_message "git pull --ff-only failed (local commits/diverged?). Continuing with current tree."
  fi
fi

# --------------------------
# Guarded system upgrade (always)
# --------------------------

if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
  sudo -v
fi

{
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
  done
} &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

ensure_yay_installed || print_warning_message "yay install failed — AUR steps may fail"

set +e
if [ "$ASSUME_YES" = true ]; then
  safe_system_upgrade --yes
else
  safe_system_upgrade
fi
UPGRADE_RC=$?
set -e
if [ "$UPGRADE_RC" -eq 0 ]; then
  record_system_upgrade_stamps
else
  print_warning_message "Guarded system update failed — continuing with link/setup/cleanup."
fi

# --------------------------
# Re-apply setup scripts (idempotent)
# --------------------------

if [ "$SKIP_BOOTSTRAP" = false ]; then
  print_line_break "Running setup scripts (safe to re-run)"

  export SETUP_PROFILES SETUP_PROFILE FULL_NAME EMAIL_ADDRESS INSTALL_NVIDIA MACHINE_TYPE
  export SETUP_CONTINUE_ON_ERROR=true
  if [ "$ASSUME_YES" = true ]; then
    export DOTFILES_AUR_ASSUME_YES=true
  else
    unset DOTFILES_AUR_ASSUME_YES 2>/dev/null || true
  fi
  set +e
  bash "$DF_SCRIPT_DIR/run-profile-setup.sh"
  SETUP_RC=$?
  set -e
  if [ "$SETUP_RC" -ne 0 ]; then
    print_warning_message "Some setup scripts failed (see above). Continuing with link/cleanup."
  fi
else
  print_info_message "Skipping setup scripts (--skip-bootstrap)"
fi

# --------------------------
# Relink dotfiles
# --------------------------

print_line_break "Linking dotfiles"
bash "$DF_SCRIPT_DIR/link-dotfiles.sh" "$(format_setup_profiles)"
bash "$DF_SCRIPT_DIR/post-link-hooks.sh"

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
  print_line_break "Cleaning obsolete packages / configs"

  collect_obsolete_pkgs
  local pkgs_to_remove=("${OBSOLETE_PKGS_INSTALLED[@]}")

  if [ ${#pkgs_to_remove[@]} -gt 0 ]; then
    print_action_message "Will remove: ${pkgs_to_remove[*]}"
    if [ "$ASSUME_YES" = true ]; then
      CONFIRM_RM=y
    else
      read -rp "Remove these packages? [y/n] (Enter = $(fmt_choice "no")): " CONFIRM_RM
    fi
    if [[ "${CONFIRM_RM:-}" =~ ^[Yy]$ ]]; then
      sudo pacman -Rns --noconfirm "${pkgs_to_remove[@]}" || print_warning_message "Some packages could not be removed"
    else
      print_info_message "Kept obsolete packages"
    fi
  else
    print_info_message "No obsolete pacman packages found"
  fi

  # npm global Copilot CLI (user-level NVM npm — never sudo npm)
  if load_nvm && command -v npm &>/dev/null; then
    if npm list -g --depth=0 @githubnext/github-copilot-cli &>/dev/null 2>&1; then
      print_action_message "Removing global npm package @githubnext/github-copilot-cli"
      npm uninstall -g @githubnext/github-copilot-cli || true
    fi
  else
    print_info_message "NVM/npm not available — skip Copilot CLI cleanup"
  fi

  # Stale config dirs that are no longer linked from this repo
  local stale_dirs=(
    "$USER_HOME_DIR/.config/ghostty"
    "$USER_HOME_DIR/.config/alacritty"
    "$USER_HOME_DIR/.config/hypr"
    "$USER_HOME_DIR/.config/waybar"
    "$USER_HOME_DIR/.config/tmuxinator"
    "$USER_HOME_DIR/.config/herdr"
  )

  for dir in "${stale_dirs[@]}"; do
    if [ -e "$dir" ] || [ -L "$dir" ]; then
      if [ -L "$dir" ]; then
        local target
        target="$(readlink -f "$dir" 2>/dev/null || true)"
        if [[ "$target" == "$REPO_ROOT"* ]]; then
          continue
        fi
      fi
      print_action_message "Backing up stale config: $dir → ${dir}.obsolete.bak"
      mv "$dir" "${dir}.obsolete.bak"
    fi
  done

  local orphans
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  if [ -n "$orphans" ]; then
    print_info_message "Removing orphaned packages..."
    # shellcheck disable=SC2086
    sudo pacman -Rns --noconfirm $orphans || true
  fi
}

collect_obsolete_pkgs

if [ "$DO_CLEANUP" = true ]; then
  cleanup_obsolete
elif [ ${#OBSOLETE_PKGS_INSTALLED[@]} -eq 0 ]; then
  print_info_message "No obsolete packages installed; skipping cleanup"
elif [ "$ASSUME_YES" = false ]; then
  echo ""
  read -rp "Also remove obsolete packages (${OBSOLETE_PKGS_INSTALLED[*]})? [y/n] (Enter = $(fmt_choice "no")): " ASK_CLEAN
  if [[ "${ASK_CLEAN:-}" =~ ^[Yy]$ ]]; then
    cleanup_obsolete
  else
    print_info_message "Skipped cleanup (re-run with --cleanup later if needed)"
  fi
else
  print_info_message "Skipped cleanup (pass --cleanup with --yes to remove: ${OBSOLETE_PKGS_INSTALLED[*]})"
fi

print_line_break "Sync complete"
print_success_message "Profiles: $(format_setup_profiles)"
print_info_message "Commands on PATH (via ~/.local/bin): dfa-sync-dotfiles, dfa-update-system"
print_info_message "Restart the terminal (or log out/in) so PATH, Kitty defaults, and shell aliases refresh."
print_info_message "If GNOME shortcuts/tray/fonts look wrong: log out and back in so extensions reload."
print_info_message "Neovim: open nvim once and run :Lazy sync / :TSUpdate if plugins look stale."
print_info_message "On other machines: clone/pull this repo, then run:  dfa-sync-dotfiles   # or: bash scripts/sync.sh"
