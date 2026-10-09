#!/bin/bash

# --------------------------
# Setup NinjaOne agent for Arch Linux / Ubuntu (work machines, one-time)
# --------------------------
# NinjaOne ships the Linux agent only as a .deb/.rpm. This repackages the .deb
# as a local pacman package on Arch; Ubuntu installs the native DEB. Not in run-profile-setup.sh: run it explicitly.
# The agent updates itself afterwards; dfa-update-ninjaone (dfa-weekly) only checks health.
#
# Usage: setup-ninjaone.sh [--url <installer .deb URL>] [--force]
#   URL order: --url, then $NINJAONE_INSTALLER_URL, then the saved env file, then a prompt.
#   --force installs even when the work profile is not selected.
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

url=""
force=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) [[ $# -ge 2 && -n "$2" ]] || { print_error_message "--url requires a value"; exit 2; }; url="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --yes|-y) shift ;;
    -h|--help) sed -n '10,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print_error_message "Unknown argument (value withheld)"; exit 2 ;;
  esac
done

print_tool_setup_start "NinjaOne agent"

load_bootstrap_config
if ! has_setup_profile work && [[ "$force" != true ]]; then
  print_warning_message "Work profile not selected — skipping (use --force to override)"
  exit 0
fi

# Used by sourced NinjaOne helpers.
# shellcheck disable=SC2034
read -r owner NINJAONE_PKG < <(ninjaone_install_owner)
if [[ "$owner" == managed ]]; then
  print_warning_message "Existing IT-managed/unrecognized NinjaOne retained; health checks remain read-only"
  exit 0
fi
if [[ "$owner" == owned ]] && ninjaone_binary_present; then
  print_info_message "NinjaOne agent already installed ($(ninjaone_disk_version)) — run dfa-update-ninjaone to check health"
  exit 0
fi

ninjaone_load_url
[[ -n "$url" ]] || url="$NINJAONE_INSTALLER_URL"
if [[ -z "$url" ]]; then
  if [[ ! -t 0 ]]; then
    print_error_message "No installer URL. Pass --url, set NINJAONE_INSTALLER_URL, or run interactively."
    exit 1
  fi
  read -r -s -p "NinjaOne installer .deb URL (hidden): " url
  echo
fi

ninjaone_build_and_install "$url" || {
  print_error_message "NinjaOne agent installation failed"
  exit 1
}
ninjaone_save_url "$url"

print_success_message "NinjaOne agent installed ($(ninjaone_disk_version)); installer URL saved to $(ninjaone_env_file)"
if [[ "$WORKSTATION_DISTRO" == arch ]]; then
  print_info_message "Known limitations: Arch is unsupported by NinjaOne; console uninstall calls dpkg. Use dfa-uninstall-ninjaone."
else
  print_info_message "Native DEB installed; vendor agent/patcher owns updates (no added APT repository)."
fi
print_tool_setup_complete "NinjaOne agent"
