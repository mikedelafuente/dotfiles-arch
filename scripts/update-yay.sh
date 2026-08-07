#!/bin/bash
# Manual helper: rebuild yay from the AUR when the package is broken.
# Not part of bootstrap/sync — run only when needed:
#   bash scripts/update-yay.sh

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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

print_action_message "Cloning yay from AUR into $TMP"
git clone https://aur.archlinux.org/yay.git "$TMP/yay"
(
  cd "$TMP/yay" || exit 1
  makepkg -si --noconfirm
)

print_success_message "yay rebuilt: $(command -v yay)"
print_tool_setup_complete "Rebuild yay"
