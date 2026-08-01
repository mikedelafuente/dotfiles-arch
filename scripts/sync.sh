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
# Flags:
#   --profile work|personal   Set/force profile (prompted if unset)
#   --cleanup                 Remove obsolete packages (tmux, ghostty, etc.)
#   --skip-bootstrap          Only pull + link + cleanup; skip setup-*.sh runs
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

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Bring this machine in line with the current dotfiles-arch repo.

Options:
  --profile work|personal   Set profile (required with --yes if none is saved)
  --cleanup                 Remove obsolete packages (tmux, ghostty, etc.)
  --skip-bootstrap          Only pull + link + cleanup; skip setup-*.sh runs
  --yes, -y                 Non-interactive where safe
  -h, --help                Show this help

If no profile is saved yet, sync will prompt you to choose work or personal.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
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
# Resolve profile
# --------------------------

BOOTSTRAP_CONFIG_DIR="$USER_HOME_DIR/.config/dotfiles-arch"
mkdir -p "$BOOTSTRAP_CONFIG_DIR"
CONFIG_FILE="$BOOTSTRAP_CONFIG_DIR/.dotfiles_bootstrap_config"

SAVED_PROFILE=""
if [ -r "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  SAVED_PROFILE="${SETUP_PROFILE:-}"
fi

# Migrate legacy name from saved config
if [ "${SAVED_PROFILE}" = "productivity" ]; then
  SAVED_PROFILE="work"
fi

normalize_profile() {
  case "$1" in
    1|work|Work|WORK|productivity|Productivity) echo "work" ;;
    2|personal|Personal|PERSONAL) echo "personal" ;;
    *) return 1 ;;
  esac
}

SETUP_PROFILE=""
PROFILE_WAS_UNSET=false

if [ -n "$FORCE_PROFILE" ]; then
  if ! SETUP_PROFILE="$(normalize_profile "$FORCE_PROFILE")"; then
    print_error_message "Invalid --profile '$FORCE_PROFILE' (use work or personal)"
    exit 1
  fi
elif [ -n "$SAVED_PROFILE" ]; then
  if ! SETUP_PROFILE="$(normalize_profile "$SAVED_PROFILE")"; then
    print_warning_message "Saved profile '$SAVED_PROFILE' is invalid; you'll need to choose again"
    PROFILE_WAS_UNSET=true
    SETUP_PROFILE=""
  fi
else
  PROFILE_WAS_UNSET=true
fi

if [ -z "$SETUP_PROFILE" ]; then
  if [ "$ASSUME_YES" = true ]; then
    print_error_message "No profile is set. Pass --profile work|personal (required with --yes)."
    exit 1
  fi

  echo ""
  print_info_message "No setup profile is configured for this machine yet."
  echo "Select which profile to use:"
  echo "  1) work      — shared stack + Zoom + Slack + Chrome"
  echo "  2) personal — shared stack + Steam + Discord + Firefox + Mullvad"
  while true; do
    read -rp "Profile [1=work, 2=personal]: " PROFILE_INPUT
    if SETUP_PROFILE="$(normalize_profile "${PROFILE_INPUT:-}")"; then
      break
    fi
    print_warning_message "Please choose 1/work or 2/personal"
  done
elif [ "$ASSUME_YES" = false ]; then
  echo ""
  if [ "$PROFILE_WAS_UNSET" = true ]; then
    print_info_message "Choose a setup profile for this machine:"
  else
    print_info_message "Current saved profile: $SETUP_PROFILE"
  fi
  echo "  1) work      — shared stack + Zoom + Slack + Chrome"
  echo "  2) personal — shared stack + Steam + Discord + Firefox + Mullvad"
  read -rp "Profile [1=work, 2=personal] (Enter keeps '$SETUP_PROFILE'): " PROFILE_INPUT
  if [ -n "${PROFILE_INPUT:-}" ]; then
    if ! SETUP_PROFILE="$(normalize_profile "$PROFILE_INPUT")"; then
      print_error_message "Unknown choice '$PROFILE_INPUT'"
      exit 1
    fi
  fi
fi

if [[ "$SETUP_PROFILE" != "work" && "$SETUP_PROFILE" != "personal" ]]; then
  print_error_message "Profile must be 'work' or 'personal' (got: $SETUP_PROFILE)"
  exit 1
fi

# Preserve identity fields; refresh profile
FULL_NAME="${FULL_NAME:-}"
EMAIL_ADDRESS="${EMAIL_ADDRESS:-}"
{
  echo "# Configuration file for dotfiles bootstrap script"
  echo "FULL_NAME=\"$FULL_NAME\""
  echo "EMAIL_ADDRESS=\"$EMAIL_ADDRESS\""
  echo "SETUP_PROFILE=\"$SETUP_PROFILE\""
} > "$CONFIG_FILE"

print_line_break "Syncing machine to dotfiles-arch ($SETUP_PROFILE)"
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
# Re-apply setup scripts (idempotent)
# --------------------------

if [ "$SKIP_BOOTSTRAP" = false ]; then
  print_line_break "Running setup scripts (safe to re-run)"

  if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
    sudo -v
  fi

  # Keep sudo alive
  {
    while true; do
      sudo -n true
      sleep 60
      kill -0 "$$" 2>/dev/null || exit
    done
  } &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

  run_setup() {
    local script="$1"
    if [ -f "$DF_SCRIPT_DIR/$script" ]; then
      print_info_message "→ $script"
      bash "$DF_SCRIPT_DIR/$script"
    else
      print_warning_message "Missing $script — skipped"
    fi
  }

  # Shared stack (mirrors bootstrap.sh)
  run_setup setup-essentials.sh
  if [ -n "$FULL_NAME" ] && [ -n "$EMAIL_ADDRESS" ]; then
    bash "$DF_SCRIPT_DIR/setup-git.sh" "$FULL_NAME" "$EMAIL_ADDRESS"
  else
    print_warning_message "FULL_NAME/EMAIL_ADDRESS not set — skipping setup-git.sh (re-run bootstrap once to set them)"
  fi
  run_setup setup-github-cli.sh
  run_setup setup-node.sh
  run_setup setup-fonts.sh
  run_setup setup-bash.sh
  run_setup setup-kitty.sh
  run_setup setup-cursor.sh
  run_setup setup-claude.sh
  run_setup setup-herdr.sh
  run_setup setup-python.sh
  run_setup setup-rust.sh
  run_setup setup-golang.sh
  run_setup setup-neovim.sh
  run_setup setup-tableplus.sh
  run_setup setup-docker.sh
  run_setup setup-minikube.sh
  run_setup setup-code.sh
  run_setup setup-php.sh
  run_setup setup-ruby.sh
  run_setup setup-postman.sh
  run_setup setup-moonlander.sh
  run_setup setup-spotify.sh
  run_setup setup-obsidian.sh

  if [ "$SETUP_PROFILE" = "work" ]; then
    run_setup setup-zoom.sh
    run_setup setup-slack.sh
    run_setup setup-chrome.sh
  else
    run_setup setup-steam.sh
    run_setup setup-discord.sh
    run_setup setup-firefox.sh
    run_setup setup-mullvad.sh
  fi

  if pacman -Q gnome-shell &>/dev/null; then
    run_setup setup-gnome.sh
  fi
else
  print_info_message "Skipping setup scripts (--skip-bootstrap)"
fi

# --------------------------
# Relink dotfiles
# --------------------------

print_line_break "Linking dotfiles"
bash "$DF_SCRIPT_DIR/link-dotfiles.sh" "$SETUP_PROFILE"

# --------------------------
# Optional cleanup of obsolete tooling
# --------------------------

cleanup_obsolete() {
  print_line_break "Cleaning obsolete packages / configs"

  local pkgs_to_remove=()
  local candidates=(
    tmux
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

  for pkg in "${candidates[@]}"; do
    if pacman -Q "$pkg" &>/dev/null; then
      pkgs_to_remove+=("$pkg")
    fi
  done

  if [ ${#pkgs_to_remove[@]} -gt 0 ]; then
    print_action_message "Will remove: ${pkgs_to_remove[*]}"
    if [ "$ASSUME_YES" = true ]; then
      CONFIRM_RM=y
    else
      read -rp "Remove these packages? [y/N]: " CONFIRM_RM
    fi
    if [[ "${CONFIRM_RM:-}" =~ ^[Yy]$ ]]; then
      sudo pacman -Rns --noconfirm "${pkgs_to_remove[@]}" || print_warning_message "Some packages could not be removed"
    else
      print_info_message "Kept obsolete packages"
    fi
  else
    print_info_message "No obsolete pacman packages found"
  fi

  # npm global Copilot CLI
  if command -v npm &>/dev/null && npm list -g --depth=0 @githubnext/github-copilot-cli &>/dev/null 2>&1; then
    print_action_message "Removing global npm package @githubnext/github-copilot-cli"
    sudo npm uninstall -g @githubnext/github-copilot-cli || true
  fi

  # Stale config dirs that are no longer linked from this repo
  local stale_dirs=(
    "$USER_HOME_DIR/.config/ghostty"
    "$USER_HOME_DIR/.config/alacritty"
    "$USER_HOME_DIR/.config/hypr"
    "$USER_HOME_DIR/.config/waybar"
    "$USER_HOME_DIR/.config/tmuxinator"
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

  if [ -e "$USER_HOME_DIR/.tmux.conf" ] && [ ! -L "$USER_HOME_DIR/.tmux.conf" ]; then
    print_action_message "Backing up ~/.tmux.conf → ~/.tmux.conf.obsolete.bak"
    mv "$USER_HOME_DIR/.tmux.conf" "$USER_HOME_DIR/.tmux.conf.obsolete.bak"
  elif [ -L "$USER_HOME_DIR/.tmux.conf" ]; then
    print_action_message "Removing leftover ~/.tmux.conf symlink"
    rm -f "$USER_HOME_DIR/.tmux.conf"
  fi

  local orphans
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  if [ -n "$orphans" ]; then
    print_info_message "Removing orphaned packages..."
    # shellcheck disable=SC2086
    sudo pacman -Rns --noconfirm $orphans || true
  fi
}

if [ "$DO_CLEANUP" = true ]; then
  cleanup_obsolete
elif [ "$ASSUME_YES" = false ]; then
  echo ""
  read -rp "Also remove obsolete packages (tmux, ghostty, alacritty, hyprland, …)? [y/N]: " ASK_CLEAN
  if [[ "${ASK_CLEAN:-}" =~ ^[Yy]$ ]]; then
    cleanup_obsolete
  else
    print_info_message "Skipped cleanup (re-run with --cleanup later if needed)"
  fi
else
  print_info_message "Skipped cleanup (pass --cleanup with --yes to remove obsolete packages)"
fi

print_line_break "Sync complete"
print_success_message "Profile: $SETUP_PROFILE"
print_info_message "Restart the terminal (or log out/in) so PATH, Kitty defaults, and shell aliases refresh."
print_info_message "Neovim: open nvim once and run :Lazy sync / :TSUpdate if plugins look stale."
print_info_message "On other machines: clone/pull this repo, then run:  bash scripts/sync.sh"
