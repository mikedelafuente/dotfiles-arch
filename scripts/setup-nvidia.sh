#!/bin/bash
# --------------------------
# Setup NVIDIA drivers (optional)
# --------------------------
# Installs nvidia-open-dkms + utils when this machine should use NVIDIA drivers.
#
# Decision order:
#   1. INSTALL_NVIDIA=true|false from env / bootstrap config (explicit)
#   2. --yes / non-interactive: install only if packages already present OR hardware detected
#   3. Interactive: prompt, defaulting to yes when packages or hardware are detected
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

ASSUME_YES=false
FORCE_INSTALL=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --install) FORCE_INSTALL=true ;;
    --skip) FORCE_INSTALL=false ;;
  esac
done

# Load saved bootstrap preference when not already set
if [ -z "${INSTALL_NVIDIA:-}" ]; then
  load_bootstrap_config || true
fi

print_tool_setup_start "NVIDIA drivers"

PACKAGES_PRESENT=false
DRIVER_PRESENT=false
HARDWARE_PRESENT=false
if has_nvidia_packages; then
  PACKAGES_PRESENT=true
fi
if [[ -n "$(nvidia_driver_packages)" ]]; then
  DRIVER_PRESENT=true
fi
if has_nvidia_hardware; then
  HARDWARE_PRESENT=true
fi

print_info_message "NVIDIA packages installed: $PACKAGES_PRESENT"
print_info_message "NVIDIA driver module present: $DRIVER_PRESENT$([ "$DRIVER_PRESENT" = true ] && printf ' (%s)' "$(nvidia_driver_packages | paste -sd, -)")"
print_info_message "NVIDIA hardware detected:  $HARDWARE_PRESENT"

should_install=""
if [ -n "$FORCE_INSTALL" ]; then
  should_install="$FORCE_INSTALL"
elif [[ "${INSTALL_NVIDIA:-}" == "true" || "${INSTALL_NVIDIA:-}" == "1" || "${INSTALL_NVIDIA:-}" == "yes" || "${INSTALL_NVIDIA:-}" == "y" ]]; then
  should_install=true
elif [[ "${INSTALL_NVIDIA:-}" == "false" || "${INSTALL_NVIDIA:-}" == "0" || "${INSTALL_NVIDIA:-}" == "no" || "${INSTALL_NVIDIA:-}" == "n" ]]; then
  should_install=false
fi

if [ -z "$should_install" ]; then
  # No explicit preference — detect / prompt (or auto with --yes)
  export ASSUME_YES
  resolve_nvidia_preference
  should_install="$INSTALL_NVIDIA"
fi

# Persist preference for bootstrap/sync (preserve other identity fields)
_nvidia_decision="$should_install"
load_bootstrap_config || true
INSTALL_NVIDIA="$_nvidia_decision"
unset _nvidia_decision
write_bootstrap_config

if [ "$should_install" != true ]; then
  print_info_message "Skipping NVIDIA driver install (INSTALL_NVIDIA=false)"
  print_tool_setup_complete "NVIDIA drivers"
  exit 0
fi

# Never swap driver flavors (nvidia-open vs nvidia-open-dkms conflict).
if [ "$DRIVER_PRESENT" = true ]; then
  print_info_message "NVIDIA kernel module already installed — leaving flavor alone, ensuring utils/settings/headers"
  sudo pacman -S --needed --noconfirm nvidia-utils nvidia-settings linux-headers
elif [ "$PACKAGES_PRESENT" = true ]; then
  print_info_message "NVIDIA utils present without a module package — installing nvidia-open-dkms"
  sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings linux-headers
else
  print_action_message "Installing NVIDIA open DKMS drivers (Turing+)"
  sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils nvidia-settings linux-headers
fi

print_success_message "NVIDIA drivers ready"
print_tool_setup_complete "NVIDIA drivers"
