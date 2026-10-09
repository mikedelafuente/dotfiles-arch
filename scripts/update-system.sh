#!/bin/bash
# --------------------------
# Guarded day-to-day system updater
# --------------------------
# Arch: pacman + guarded AUR updates. Ubuntu 26.04: native APT upgrade.
#
# Usage:
#   bash scripts/update-system.sh           # interactive native update prompts
#   bash scripts/update-system.sh --yes     # non-interactive after clean scan
#   bash scripts/update-system.sh --scan-only
#   bash scripts/update-system.sh --force   # bypass the cooldown check
#
# Skips the actual upgrade (no prompts, no sudo) when the last guarded
# upgrade ran within the last 24h, using the same cooldown stamps bootstrap
# writes/reads (record_system_upgrade_stamps / system_upgrade_cooldown_expired
# in fn-lib.sh). Pass --force to upgrade anyway.
#
# Prefer this over raw `yay -Syu` for daily use.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# fn-lib.sh already sources this (its own ensure_yay_pkgs/safe_system_upgrade
# need it), but sourced explicitly here too since this script calls
# aur_scan_pending_upgrades directly — keeps the dependency visible locally
# even if fn-lib.sh's internal wiring ever changes.
# shellcheck source=/dev/null
source "$CURRENT_FILE_DIR/aur-lib.sh"

ASSUME_YES=false
SCAN_ONLY=false
FORCE=false

usage() {
  cat <<'EOF'
System updater (Arch: pacman + guarded AUR; Ubuntu 26.04: APT; managed CLI releases)

Usage:
  bash scripts/update-system.sh [options]

Options:
  --yes, -y       Non-interactive native updates (Arch: after clean IoC scan)
  --scan-only     Arch: scan pending AUR upgrades; Ubuntu: diagnostic only
  --force         Upgrade even if the 1-day cooldown hasn't expired
  -h, --help      Show this help

Arch scans AUR PKGBUILDs and dependencies before yay upgrades. Ubuntu uses
configured APT sources, retains holds/pins and automatic security updates,
and refuses removals. Release upgrades are excluded. --yes is not cleanup approval.
Managed upstream Neovim/tree-sitter/lazydocker/minikube/kubectl/k9s and existing Ubuntu Orca/Zoom DEBs refresh
after native updates. Ubuntu Zed user installs and Orca AppImages use their in-app
self-updaters (keep enabled); DEB notifications alone do not install updates.
Chrome/Slack use scoped vendor APT sources; source and candidate conflicts fail.
Zoom DEBs require a pinned vendor signature and matching archive-member hashes.
TablePlus/Spotify use scoped vendor APT; Obsidian's installer/Electron DEB and
pinned Keymapp archive refresh separately. Changed Keymapp bytes require a reviewed
pin update. Existing official Spotify/Postman Snaps retain automatic updates/holds;
writable user Postman archives retain in-app updates (keep enabled).
Other downloads require stable release metadata and SHA-256 verification; any failure
retains the working release and prevents a successful-update stamp.

Skips the actual upgrade (no prompts, no sudo) when the last guarded upgrade
ran within the last 24h; pass --force to upgrade anyway.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --scan-only) SCAN_ONLY=true ;;
    --force) FORCE=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print_error_message "Unknown option: $arg"
      usage
      exit 1
      ;;
  esac
done

if [ "$SCAN_ONLY" = true ]; then
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    print_info_message "AUR scan-only is Arch-specific; Ubuntu uses APT. No scan or update performed."
    exit 0
  fi
  print_line_break "AUR upgrade scan only"
  aur_scan_pending_upgrades
  exit $?
fi

if [ "$FORCE" != true ] && ! system_upgrade_cooldown_expired; then
  print_info_message "Checked recently (within the last 24h) — skipping guarded upgrade. Use --force to override."
  exit 0
fi

# Authenticate for the selected native update backend
if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
  sudo -v
fi

if [ "$ASSUME_YES" = true ]; then
  if safe_system_upgrade --yes; then
    record_system_upgrade_stamps || exit 1
  else
    print_error_message "Guarded system update failed"
    exit 1
  fi
else
  if safe_system_upgrade; then
    record_system_upgrade_stamps || exit 1
  else
    print_error_message "Guarded system update failed"
    exit 1
  fi
fi

if [[ "$WORKSTATION_DISTRO" == arch ]]; then
  print_info_message "Tip: use this instead of raw 'yay -Syu' day to day."
  print_info_message "Re-run with --scan-only anytime to check pending AUR upgrades without installing."
fi

# Snapper rollback reminder (Btrfs installs from user_configuration.json)
if command -v snapper &>/dev/null && sudo snapper list-configs 2>/dev/null | grep -qw root; then
  print_info_message "Snapper: 'sudo snapper -c root list' shows snapshots; 'sudo snapper -c root create -d \"before <change>\"' before risky upgrades."
fi
