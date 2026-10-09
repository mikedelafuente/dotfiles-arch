#!/usr/bin/env bash
# Shared Keymapp and vendor ZSA permissions. Never replace unrelated udev rules.
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "ZSA Keymapp"
UDEV_RULES_FILE=/etc/udev/rules.d/50-zsa.rules
UDEV_RULES_SOURCE="$DF_SCRIPT_DIR/zsa-udev.rules"
[[ ! -L /etc/udev/rules.d && ! -L "$UDEV_RULES_FILE" ]] || {
  print_error_message 'ZSA udev path conflict; preserved'; exit 1;
}
# Existing compatible rules (including user comments/additions) stay untouched.
if [[ -e "$UDEV_RULES_FILE" ]]; then
  [[ -f "$UDEV_RULES_FILE" && -r "$UDEV_RULES_FILE" ]] || exit 1
  while IFS= read -r rule; do
    [[ -z "$rule" || "$rule" == \#* ]] && continue
    grep -Fxq "$rule" "$UDEV_RULES_FILE" || {
      print_error_message 'Existing ZSA udev rules differ; review/merge required, file preserved'; exit 1;
    }
  done <"$UDEV_RULES_SOURCE"
fi
ensure_desktop_utility keymapp || exit 1
REAL_USER="${SUDO_USER:-$(whoami)}"
getent group plugdev &>/dev/null || sudo groupadd plugdev || exit 1
if ! id -nG "$REAL_USER" | grep -qw plugdev; then
  sudo usermod -aG plugdev "$REAL_USER" || exit 1
  print_warning_message 'Log out and back in for plugdev membership to apply'
fi
if [[ ! -e "$UDEV_RULES_FILE" ]]; then
  sudo install -d -m755 /etc/udev/rules.d || exit 1
  sudo install -m644 "$UDEV_RULES_SOURCE" "$UDEV_RULES_FILE" || exit 1
  sudo udevadm control --reload-rules || exit 1
  print_info_message 'Replug the keyboard to apply permissions (no global device trigger)'
fi
print_info_message 'Keymapp requires GTK3, WebKitGTK 4.1 and libusb; Wayland/USB/flashing runtime unverified'
print_tool_setup_complete "ZSA Keymapp"
