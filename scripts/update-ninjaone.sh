#!/bin/bash

# --------------------------
# NinjaOne agent health check / forced upgrade
# --------------------------
# The agent upgrades itself (ninjarmm-patcher.timer), so a plain run only checks health
# and reinstalls from the saved URL when the agent is missing. Quietly exits 0 when it
# was never installed with setup-ninjaone.sh.
#
# Usage: update-ninjaone.sh [--url <newer installer .deb URL>] [--yes]
#   --url upgrades only when that version is newer than what is on disk.
#   Other args from dfa-weekly (--force, ...) are ignored.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi
# shellcheck source=/dev/null
source "$CURRENT_FILE_DIR/ninjaone-lib.sh"

new_url=""
assume_yes=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) new_url="${2:-}"; shift 2 ;;
    --yes|-y) assume_yes=true; shift ;;
    -h|--help) sed -n '10,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

print_line_break "NinjaOne agent"

if ! ninjaone_pkg_installed && ! ninjaone_binary_present; then
  print_info_message "NinjaOne agent not installed — skip (install with dfa-install-ninjaone)"
  exit 0
fi

ninjaone_load_url

if [[ -n "$new_url" ]]; then
  ninjaone_url_valid "$new_url" || {
    print_error_message "URL must be https://<region>.ninjarmm.com/agent/installer/<uid>/<version>/<name>.deb"
    exit 1
  }
  current="$(ninjaone_disk_version)"
  target="$(ninjaone_url_version "$new_url")"
  if ! ninjaone_version_gt "$target" "$current"; then
    print_info_message "Installed $current is not older than $target — nothing to do"
    exit 0
  fi
  if [[ "$assume_yes" != true ]]; then
    read -r -p "Upgrade NinjaOne agent $current -> $target? [Y/n] " reply
    [[ "${reply:-Y}" =~ ^[Yy] ]] || exit 0
  fi
  ninjaone_build_and_install "$new_url" || exit 1
  ninjaone_save_url "$new_url"
  print_success_message "NinjaOne agent upgraded to $(ninjaone_disk_version)"
  exit 0
fi

if ! ninjaone_binary_present; then
  print_warning_message "Agent binary missing — reinstalling from saved URL"
  [[ -n "$NINJAONE_INSTALLER_URL" ]] || {
    print_error_message "No saved installer URL. Run: dfa-update-ninjaone --url <URL>"
    exit 1
  }
  ninjaone_build_and_install "$NINJAONE_INSTALLER_URL" || exit 1
fi

ensure_pacman_pkgs "${NINJAONE_RUNTIME_DEPS[@]}"

status=0
for unit in ninjarmm-agent.service ninjarmm-patcher.timer; do
  if ! systemctl is-active --quiet "$unit"; then
    print_warning_message "$unit not active — enabling and starting"
    sudo systemctl enable --now "$unit" || status=1
  fi
done
systemctl is-enabled --quiet ninjarmm-patcher.timer || sudo systemctl enable ninjarmm-patcher.timer || status=1

if [[ $status -eq 0 ]]; then
  print_success_message "NinjaOne agent healthy ($(ninjaone_disk_version)); self-updates via ninjarmm-patcher.timer"
else
  print_error_message "NinjaOne agent unhealthy — see: systemctl status ninjarmm-agent.service"
fi
exit "$status"
