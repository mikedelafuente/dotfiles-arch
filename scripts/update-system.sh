#!/bin/bash
# --------------------------
# Guarded day-to-day system updater
# --------------------------
# Equivalent of:  sudo pacman -Syu && yay -Syu
# with AUR PKGBUILD IoC scanning (Atomic Arch / curl|sh footguns) first.
#
# Usage:
#   bash scripts/update-system.sh           # interactive pacman/yay prompts
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
Guarded system updater (pacman + yay with AUR security scan)

Usage:
  bash scripts/update-system.sh [options]

Options:
  --yes, -y       Non-interactive (--noconfirm) after IoC scan passes
  --scan-only     Only scan pending AUR upgrades; do not install
  --force         Upgrade even if the 1-day cooldown hasn't expired
  -h, --help      Show this help

Scans AUR PKGBUILDs for known supply-chain IoCs (e.g. Atomic Arch) before
upgrading. Official repos (core/extra/multilib) are updated via pacman.

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
  print_line_break "AUR upgrade scan only"
  aur_scan_pending_upgrades
  exit $?
fi

if [ "$FORCE" != true ] && ! system_upgrade_cooldown_expired; then
  print_info_message "Checked recently (within the last 24h) — skipping guarded upgrade. Use --force to override."
  exit 0
fi

# Keep sudo warm for pacman
if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
  sudo -v
fi

if [ "$ASSUME_YES" = true ]; then
  if safe_system_upgrade --yes; then
    record_system_upgrade_stamps
  else
    print_error_message "Guarded system update failed"
    exit 1
  fi
else
  if safe_system_upgrade; then
    record_system_upgrade_stamps
  else
    print_error_message "Guarded system update failed"
    exit 1
  fi
fi

print_info_message "Tip: use this instead of raw 'yay -Syu' day to day."
print_info_message "Re-run with --scan-only anytime to check pending AUR upgrades without installing."

# Snapper rollback reminder (Btrfs installs from user_configuration.json)
if command -v snapper &>/dev/null && sudo snapper list-configs 2>/dev/null | grep -qw root; then
  print_info_message "Snapper: 'sudo snapper -c root list' shows snapshots; 'sudo snapper -c root create -d \"before <change>\"' before risky upgrades."
fi
