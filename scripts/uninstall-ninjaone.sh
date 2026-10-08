#!/bin/bash

# --------------------------
# Remove the NinjaOne agent and the SentinelOne agent it installed
# --------------------------
# Safe to re-run; every step skips what is already gone. dpkg, dmidecode, inetutils
# and lsof are left installed (they are useful on their own).
#
# Usage: uninstall-ninjaone.sh [--yes] [--keep-url]
#   --keep-url keeps the saved installer URL so dfa-install-ninjaone can reinstall later.
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

assume_yes=false
keep_url=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) assume_yes=true ;;
    --keep-url) keep_url=true ;;
    -h|--help) sed -n '9,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print_error_message "Unknown argument: $arg"; exit 2 ;;
  esac
done

print_tool_setup_start "NinjaOne + SentinelOne removal"

if [[ "$assume_yes" != true ]]; then
  print_warning_message "This removes NinjaOne and SentinelOne; the machine stops being managed until reinstalled."
  read -r -p "Continue? [y/N] " reply
  [[ "${reply:-N}" =~ ^[Yy] ]] || exit 0
fi

sudo -v || {
  print_error_message "sudo needs a terminal; run this from a real shell"
  exit 1
}

# SentinelOne first: the NinjaOne agent would otherwise try to reinstall it.
if systemctl cat sentinelone.service &>/dev/null; then
  print_action_message "Stopping sentinelone.service"
  sudo systemctl disable --now sentinelone.service || true
fi

if [[ -x /var/lib/dpkg/info/sentinelagent.prerm ]] || sudo test -d /opt/sentinelone; then
  if command -v dpkg &>/dev/null && dpkg -s sentinelagent &>/dev/null; then
    print_action_message "Purging SentinelOne package (dpkg)"
    sudo dpkg --purge --force-remove-reinstreq --force-depends sentinelagent || \
      print_warning_message "dpkg purge reported errors; cleaning up manually"
  fi
  print_action_message "Removing SentinelOne files, account and service unit"
  sudo rm -rf /opt/sentinelone /tmp/sentinel_install.log /tmp/sentinel_uninstall.log /tmp/sentinel_should_start_after_upgrade
  sudo rm -f /usr/lib/systemd/system/sentinelone.service /etc/systemd/system/multi-user.target.wants/sentinelone.service /bin/sentinelctl /usr/bin/sentinelctl
  getent passwd sentinelone &>/dev/null && sudo userdel sentinelone
  getent group sentinelone &>/dev/null && sudo groupdel sentinelone
  sudo systemctl daemon-reload
else
  print_info_message "SentinelOne not present — skip"
fi

if ninjaone_pkg_installed; then
  print_action_message "Removing $NINJAONE_PKG (stops services, deletes /opt/NinjaRMMAgent)"
  sudo pacman -Rns --noconfirm "$NINJAONE_PKG"
elif sudo test -d /opt/NinjaRMMAgent; then
  print_warning_message "Agent files exist without the pacman package — removing manually"
  sudo systemctl disable --now ninjarmm-agent.service ninjarmm-patcher.timer ninjarmm-patcher.service || true
  sudo rm -rf /opt/NinjaRMMAgent
else
  print_info_message "NinjaOne agent not present — skip"
fi

if [[ "$keep_url" != true ]]; then
  rm -f "$(ninjaone_env_file)"
  print_info_message "Removed saved installer URL"
fi

print_info_message "The device record stays in the NinjaOne console until an admin deletes it."
print_tool_setup_complete "NinjaOne + SentinelOne removal"
