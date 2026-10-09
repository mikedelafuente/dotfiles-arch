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


print_tool_setup_start "Kubernetes tools"

ensure_core_cli curl && ensure_core_cli jq || exit 1
case "$WORKSTATION_DISTRO" in
  arch) ensure_native_pkgs python tar gzip ca-certificates ;;
  ubuntu) ensure_native_pkgs python3 tar gzip ca-certificates ;;
esac || exit 1
for app in minikube kubectl k9s; do
  ensure_kubernetes_tool "$app" || exit 1
done

print_info_message "minikube, kubectl and k9s commands available; no cluster was started"
print_info_message "Next: minikube start --driver=docker (requires Docker service and applied group membership)"
print_info_message "kubectl must be within one minor version of your cluster; resolve versions explicitly for older clusters"
print_tool_setup_complete "Kubernetes tools"
