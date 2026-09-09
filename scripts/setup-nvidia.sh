#!/bin/bash
# --------------------------
# Setup NVIDIA drivers
# --------------------------
# Installs/removes the NVIDIA open DKMS driver stack. Two invocation modes:
#
#   --install / --uninstall <packages...>
#     The dfa Catalog Engine's System Adapter path — the "nvidia" catalog
#     item (dfa/catalog/items/nvidia.toml), gated on the "nvidia-gpu"
#     Capability. Installs/removes exactly the given pacman packages via the
#     shared ensure_pacman_pkgs/remove_pacman_pkgs helpers, the same
#     convention as setup-essentials.sh. No preference is read or persisted
#     here — the Catalog Engine only calls this when the capability is met
#     (or when the user explicitly asks to uninstall).
#
#   Direct invocation (run-profile-setup.sh, always passed --yes):
#     Auto-installs only when NVIDIA hardware or an existing NVIDIA package
#     is detected on this machine. No prompt, no persisted preference.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

case "${1:-}" in
  --install)
    shift
    ensure_pacman_pkgs "$@"
    exit $?
    ;;
  --uninstall)
    shift
    remove_pacman_pkgs "$@"
    exit $?
    ;;
esac

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

if [ "$PACKAGES_PRESENT" != true ] && [ "$HARDWARE_PRESENT" != true ]; then
  print_info_message "No NVIDIA hardware or packages detected — skipping NVIDIA driver install"
  print_tool_setup_complete "NVIDIA drivers"
  exit 0
fi

# Never swap driver flavors (nvidia-open vs nvidia-open-dkms conflict).
if [ "$DRIVER_PRESENT" = true ]; then
  print_info_message "NVIDIA kernel module already installed — leaving flavor alone, ensuring utils/settings/headers"
  ensure_pacman_pkgs nvidia-utils nvidia-settings linux-headers
elif [ "$PACKAGES_PRESENT" = true ]; then
  print_info_message "NVIDIA utils present without a module package — installing nvidia-open-dkms"
  ensure_pacman_pkgs nvidia-open-dkms nvidia-utils nvidia-settings linux-headers
else
  print_action_message "Installing NVIDIA open DKMS drivers (Turing+)"
  ensure_pacman_pkgs nvidia-open-dkms nvidia-utils nvidia-settings linux-headers
fi

print_success_message "NVIDIA drivers ready"
print_tool_setup_complete "NVIDIA drivers"
