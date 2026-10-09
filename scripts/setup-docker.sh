#!/bin/bash
# Container tooling for rolling Arch / Ubuntu 26.04. Safe to rerun.

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# source header (uses SCRIPT_DIR and loads lib.sh)
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi


print_tool_setup_start "Docker"

ensure_docker_components || exit 1
# LazyDocker shares the existing native/verified release selection and updater.
case "$WORKSTATION_DISTRO" in
  arch) ensure_native_pkgs python tar gzip ca-certificates ;;
  ubuntu) ensure_native_pkgs python3 tar gzip ca-certificates ;;
esac || exit 1
ensure_core_cli curl && ensure_editor_tool lazydocker || exit 1

print_info_message "Enabling Docker Engine service"
sudo systemctl enable --now docker.service || exit 1
TARGET_USER="${SUDO_USER:-$USER}"
if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -Fxq docker; then
  sudo usermod -aG docker "$TARGET_USER" || exit 1
  print_warning_message "Docker group grants root-equivalent access; log out/in to apply membership"
fi
print_info_message "Engine, Compose and Buildx commands available; daemon/networking readiness unverified"
print_tool_setup_complete "Docker"
