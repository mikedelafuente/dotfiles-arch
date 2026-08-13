#!/bin/bash
# --------------------------
# Post-link hooks
# --------------------------
# Run after link-dotfiles.sh so freshly linked configs (e.g. fontconfig)
# are visible to the system.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_line_break "Post-link hooks"

# Fontconfig + packages are useful only after fonts.conf is linked
refresh_font_cache

if pacman -Q gnome-shell &>/dev/null; then
  print_warning_message "GNOME checklist (log out/in if anything below is missing):"
  print_info_message "  • Super+V  — clipboard history (GPaste)"
  print_info_message "  • Super+Y  — Pop Shell auto-tiling toggle (off by default)"
  print_info_message "  • Super+Escape — Pop Shell adjustment mode"
  print_info_message "  • AppIndicator tray icons for Slack/Discord/Spotify"
  print_info_message "  • Adwaita Sans UI fonts (not Courier-like fallbacks)"
fi

print_success_message "Post-link hooks complete"
