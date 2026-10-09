#!/bin/bash

# --------------------------
# Remove the NinjaOne agent and the SentinelOne agent it installed
# --------------------------
# Safe to re-run; every step skips what is already gone. dpkg, dmidecode, inetutils
# and lsof are left installed (they are useful on their own).
#
# Usage: uninstall-ninjaone.sh [--keep-url] [--remove-sentinelone]
#   Requires a terminal and typing remove; --yes alone is insufficient.
#   Ubuntu preserves SentinelOne unless --remove-sentinelone is explicitly requested.
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

keep_url=false
remove_sentinelone=false
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ;;
    --keep-url) keep_url=true ;;
    --remove-sentinelone) remove_sentinelone=true ;;
    -h|--help) sed -n '9,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print_error_message "Unknown argument: $arg"; exit 2 ;;
  esac
done

print_tool_setup_start "NinjaOne + SentinelOne removal"

read -r owner NINJAONE_PKG < <(ninjaone_install_owner)
if [[ "$owner" == managed ]]; then
  print_error_message "IT-managed/unrecognized NinjaOne retained; removal belongs to its owner"
  exit 1
fi
if [[ ! -t 0 ]]; then
  print_error_message "Removal requires a terminal and explicit confirmation; --yes is insufficient"
  exit 1
fi
print_warning_message "This removes the locally installed NinjaOne agent; the machine stops being managed."
if [[ "$WORKSTATION_DISTRO" == arch || "$remove_sentinelone" == true ]]; then
  print_warning_message "SentinelOne removal is also requested. Obtain IT approval and disable anti-tamper in its console first."
fi
read -r -p "Type remove to confirm: " reply
[[ "$reply" == remove ]] || exit 0

sudo -v || {
  print_error_message "sudo needs a terminal; run this from a real shell"
  exit 1
}

if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
  # Use the vendor's native uninstaller only for the package we installed.
  # Never copy Arch's forced dpkg/files/account/database cleanup to Ubuntu.
  if ninjaone_pkg_installed; then
    uninstaller=/opt/NinjaRMMAgent/programfiles/ninja-deb-uninstall.sh
    # The DEB may copy this file from /tmp during postinst; that source is
    # still in dpkg's file record after the temporary file is removed.
    uninstaller_owner="$(dpkg-query -S "$uninstaller" 2>/dev/null || dpkg-query -S /tmp/ninja-uninstall/ninja-deb-uninstall.sh 2>/dev/null)" || {
      print_error_message "Native uninstaller ownership unavailable; ask IT to repair it"; exit 1;
    }
    [[ "${uninstaller_owner%%: /*}" == "$NINJAONE_PKG" && -f "$uninstaller" && -x "$uninstaller" && ! -L "$uninstaller" && "$(stat -c %u "$uninstaller")" == 0 ]] || {
      print_error_message "Native uninstaller ownership mismatch; retained"; exit 1;
    }
    print_action_message "Removing native NinjaOne via its vendor uninstaller (enrollment output withheld)"
    (cd /opt/NinjaRMMAgent/programfiles && sudo "$uninstaller" >/dev/null 2>&1) || {
      print_error_message "Native uninstall failed; request vendor/IT support (no forced cleanup)"; exit 1;
    }
  fi
  if ninjaone_pkg_installed || [[ -e /opt/NinjaRMMAgent ]]; then
    print_error_message "Native agent remnants remain; request vendor/IT support (no manual deletion)"
    exit 1
  fi
  # A successful removal must not be undone by next week's missing-agent repair,
  # even when the separately requested SentinelOne removal fails afterward.
  sudo rm -f "$NINJAONE_OWNER_FILE"
  if [[ "$keep_url" != true ]]; then rm -f "$(ninjaone_env_file)"; fi
  if [[ "$remove_sentinelone" == true ]]; then
    # Presence does not prove NinjaOne enrollment: require separate named consent.
    read -r -p "Type remove SentinelOne to confirm native SentinelOne removal: " reply
    [[ "$reply" == 'remove SentinelOne' ]] || exit 1
    if dpkg-query -W -f='${Status}' sentinelagent &>/dev/null; then
      sentinelctl=/opt/sentinelone/bin/sentinelctl
      sentinel_owner="$(dpkg-query -S "$sentinelctl" 2>/dev/null)" || {
        print_error_message "SentinelOne uninstaller ownership unavailable; request IT/vendor removal"; exit 1;
      }
      [[ "${sentinel_owner%%: /*}" == sentinelagent && ! -L "$sentinelctl" ]] || {
        print_error_message "Unrecognized SentinelOne uninstaller retained; request IT/vendor removal"; exit 1;
      }
      read -r -s -p "SentinelOne uninstall passphrase from its console (hidden): " passphrase
      echo
      [[ -n "$passphrase" ]] || { print_error_message "No passphrase supplied; SentinelOne retained"; exit 1; }
      print_action_message "Removing native SentinelOne via its vendor uninstaller"
      # Keep the passphrase out of sudo's command log; only sentinelctl receives it.
      if ! printf '%s\n' "$passphrase" | sudo bash -c 'IFS= read -r passphrase; exec /opt/sentinelone/bin/sentinelctl control uninstall --passphrase "$passphrase"' >/dev/null 2>&1; then
        unset passphrase
        print_error_message "SentinelOne uninstall failed; use its console/vendor support (no forced cleanup)"; exit 1
      fi
      unset passphrase
    fi
    if native_package_installed sentinelagent || [[ -e /opt/sentinelone ]]; then
      print_error_message "SentinelOne remnants/unrecognized installation retained; request IT/vendor removal"
      exit 1
    fi
  else
    print_info_message "SentinelOne retained; --remove-sentinelone separately requests native removal"
  fi
  print_info_message "The device record stays in the NinjaOne console until an admin deletes it."
  print_tool_setup_complete "Native NinjaOne removal"
  exit 0
fi

# SentinelOne first: the NinjaOne agent would otherwise try to reinstall it.
if systemctl cat sentinelone.service &>/dev/null; then
  print_action_message "Stopping sentinelone.service"
  sudo systemctl disable --now sentinelone.service || true
fi

if dpkg -s sentinelagent &>/dev/null || sudo test -d /opt/sentinelone; then
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
  # The vendor postrm needs update-rc.d/chkconfig and exits 103 on Arch; with its scripts
  # gone dpkg can drop the package record without running them.
  if dpkg -s sentinelagent &>/dev/null; then
    print_action_message "Dropping the stuck sentinelagent record from the dpkg database"
    sudo rm -f /var/lib/dpkg/info/sentinelagent.*
    sudo dpkg --purge --force-all sentinelagent
  fi
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
