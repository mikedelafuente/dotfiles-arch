#!/bin/bash

# --------------------------
# Setup shared UI + Nerd Fonts for rolling Arch / Ubuntu 26.04
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Fonts"

read -r -a FONT_PACKAGES <<<"$(appearance_font_packages "$WORKSTATION_DISTRO")"
ensure_native_pkgs "${FONT_PACKAGES[@]}" || exit 1
if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
  ensure_ubuntu_fonts || exit 1
fi

# Early refresh; post-link-hooks.sh refreshes again after fonts.conf is linked.
refresh_font_cache
families="$(fc-list --format '%{family}\n')" || exit 1
if ! missing="$(appearance_missing_families "$families")"; then
  print_error_message "Required font families missing: $missing"
  exit 1
fi

print_tool_setup_complete "Fonts"
