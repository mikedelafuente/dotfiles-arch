#!/bin/bash
# Optional native NVIDIA setup. --yes retains saved opt-in; never opts in from PCI.
# Existing packages, modules and manual/work-managed stacks remain untouched.
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

ASSUME_YES=false
FORCE_INSTALL=''
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=true ;;
    --install) FORCE_INSTALL=true ;;
    --skip) FORCE_INSTALL=false ;;
    -h|--help)
      printf '%s\n' 'Usage: bash scripts/setup-nvidia.sh [--install|--skip] [--yes]' \
        'Only an explicit opt-in permits a new install; existing driver stacks are preserved.'
      exit 0 ;;
    *) print_error_message "Unknown NVIDIA option: $arg"; exit 1 ;;
  esac
done
export ASSUME_YES

[[ -n "${INSTALL_NVIDIA:-}" ]] || load_bootstrap_config || true
case "${FORCE_INSTALL:-${INSTALL_NVIDIA:-}}" in
  true|1|yes|y) should_install=true ;;
  false|0|no|n) should_install=false ;;
  '') resolve_nvidia_preference; should_install="$INSTALL_NVIDIA" ;;
  *) print_error_message 'Invalid INSTALL_NVIDIA preference; no driver changes'; exit 1 ;;
esac
# Keep all saved identity/profile fields through the existing accessors.
load_bootstrap_config || true
INSTALL_NVIDIA="$should_install"
write_bootstrap_config || exit 1

print_tool_setup_start 'NVIDIA drivers'
packages="$(gpu_installed_nvidia_packages)" || { print_error_message 'Cannot inspect native NVIDIA packages'; exit 1; }
stack=false
hardware=false
[[ -z "$packages" ]] || stack=true
# Presence protects an external installation; it never proves a working GPU.
if [[ -e /proc/driver/nvidia/version || -e /var/log/nvidia-installer.log ]] \
  || command -v nvidia-smi >/dev/null \
  || { command -v modinfo >/dev/null && modinfo nvidia &>/dev/null; }; then stack=true; fi
has_nvidia_hardware && hardware=true
decision="$(nvidia_setup_selection "$WORKSTATION_DISTRO" "$should_install" "$stack" "$hardware")" || exit 1
case "$decision" in
  preserve)
    print_info_message "Existing NVIDIA stack retained (${packages:-external/manual}); no driver, utils, headers or source changes"
    ;;
  skip)
    print_info_message 'Skipping NVIDIA installation (explicit opt-in and NVIDIA hardware required)'
    print_tool_setup_complete 'NVIDIA drivers'
    exit 0 ;;
  install)
    case "$WORKSTATION_DISTRO" in
      arch)
        if ! command -v lspci >/dev/null \
          || ! gpu_nvidia_open_supported "$(LC_ALL=C lspci -nn)"; then
          print_error_message 'Arch driver selection pending: cannot verify every NVIDIA GPU is Turing+. Select a compatible driver manually; no driver packages changed.'
          exit 1
        fi
        ensure_native_pkgs nvidia-open-dkms nvidia-utils nvidia-settings linux-headers || exit 1 ;;
      ubuntu)
        ensure_native_pkgs ubuntu-drivers-common || exit 1
        recommendation="$(/usr/bin/ubuntu-drivers devices)" || exit 1
        driver="$(ubuntu_nvidia_recommendation "$recommendation")" || {
          print_error_message 'No single native Ubuntu NVIDIA hardware recommendation; driver selection pending'
          exit 1
        }
        # Prefer Ubuntu's signed module for the running kernel. DKMS fallback stays
        # Ubuntu-owned and may need MOK enrollment; never add NVIDIA's CUDA repo.
        modules="linux-modules-${driver/nvidia-driver-/nvidia-}-$(uname -r)"
        candidate="$(editor_native_candidate "$modules")" || exit 1
        if [[ -n "$candidate" ]]; then
          ensure_native_pkgs "$modules" "$driver" || exit 1
        else
          print_warning_message 'Signed module unavailable for this kernel; Ubuntu DKMS activation may require Secure Boot/MOK enrollment'
          ensure_native_pkgs "$driver" || exit 1
        fi ;;
    esac ;;
esac

if [[ "$should_install" == true ]] \
  && ! { command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=driver_version --format=csv,noheader >/dev/null 2>&1; }; then
  print_warning_message 'NVIDIA activation pending: reboot, complete Secure Boot/MOK enrollment if required, and verify nvidia-smi. Existing drivers were retained.'
  exit 1
fi
print_tool_setup_complete 'NVIDIA drivers'
