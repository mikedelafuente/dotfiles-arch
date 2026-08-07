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

ASSUME_YES=false
SCAN_ONLY=false

usage() {
  cat <<'EOF'
Guarded system updater (pacman + yay with AUR security scan)

Usage:
  bash scripts/update-system.sh [options]

Options:
  --yes, -y       Non-interactive (--noconfirm) after IoC scan passes
  --scan-only     Only scan pending AUR upgrades; do not install
  -h, --help      Show this help

Scans AUR PKGBUILDs for known supply-chain IoCs (e.g. Atomic Arch) before
upgrading. Official repos (core/extra/multilib) are updated via pacman.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --scan-only) SCAN_ONLY=true ;;
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

# Keep sudo warm for pacman
if [ "$(whoami)" = "${SUDO_USER:-$(whoami)}" ]; then
  sudo -v
fi

if [ "$ASSUME_YES" = true ]; then
  safe_system_upgrade --yes
else
  safe_system_upgrade
fi

# Record timestamps used by bootstrap rate-limiting (optional convenience)
BOOTSTRAP_CONFIG_DIR="$(bootstrap_config_dir)"
mkdir -p "$BOOTSTRAP_CONFIG_DIR"
date +%s >"$BOOTSTRAP_CONFIG_DIR/.last_pacman_update"
date +%s >"$BOOTSTRAP_CONFIG_DIR/.last_pacman_upgrade"
date +%s >"$BOOTSTRAP_CONFIG_DIR/.last_yay_update"

print_info_message "Tip: use this instead of raw 'yay -Syu' day to day."
print_info_message "Re-run with --scan-only anytime to check pending AUR upgrades without installing."
