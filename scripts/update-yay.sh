#!/bin/bash
# Manual helper: rebuild yay from the AUR when the package is broken.
# Not part of bootstrap/sync — run only when needed:
#   bash scripts/update-yay.sh
#
# Removes the installed yay package (if any), then reinstalls via
# ensure_yay_installed (IoC-scanned clone + makepkg).

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
fi

print_tool_setup_start "Rebuild yay"

ensure_pacman_pkgs base-devel git

if pacman -Q yay &>/dev/null; then
  print_action_message "Removing existing yay package"
  sudo pacman -R --noconfirm yay || true
fi

# Force reinstall path: ensure_yay_installed is a no-op when yay is on PATH
hash -r 2>/dev/null || true
if ! ensure_yay_installed; then
  print_error_message "yay rebuild failed"
  exit 1
fi

print_success_message "yay rebuilt: $(command -v yay)"
print_tool_setup_complete "Rebuild yay"
