#!/bin/bash
# --------------------------
# Host prerequisites for the devcontainer
# --------------------------
# Installs CLI tools + OS config for devcontainer host setup:
#   - just, mkcert (+ nss for Firefox trust store)
#   - dig (bind) for DNS smoke checks
#   - OpenVPN 3 Linux client (AUR openvpn3 — CloudConnexa / work VPN)
#   - Cursor Dev Containers extension
#   - systemd-resolved: route ~test to 127.0.0.1:5354
#   - fs.inotify max_user_watches (large monorepo watchers)
#   - mkcert root CA trust (user-level; do not sudo mkcert -install)
#
# Shared stack already provides: Docker Engine/Compose/Buildx, GitHub CLI, Cursor IDE.
# Cert generation under .devcontainer/services/traefik/certs is left to after clone.
#
# Safe to re-run (used by bootstrap + sync).

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Devcontainer host prerequisites"

# --------------------------
# Packages
# --------------------------

# bind → dig; nss → mkcert Firefox store; just + mkcert are host CLI deps
DEVCONTAINER_PKGS=(
  bind
  just
  mkcert
  nss
)

print_info_message "Ensuring host packages: ${DEVCONTAINER_PKGS[*]}"
ensure_pacman_pkgs "${DEVCONTAINER_PKGS[@]}"

# Docker + gh live on the shared path; re-check so a standalone run still works
if ! command -v docker &>/dev/null; then
  print_warning_message "Docker not found — installing via setup-docker.sh"
  bash "$DF_SCRIPT_DIR/setup-docker.sh" || print_error_message "setup-docker.sh failed"
fi
if ! command -v gh &>/dev/null; then
  print_warning_message "GitHub CLI not found — installing via setup-github-cli.sh"
  bash "$DF_SCRIPT_DIR/setup-github-cli.sh" || print_error_message "setup-github-cli.sh failed"
fi

# --------------------------
# OpenVPN 3 Linux client (official CloudConnexa path — Arch via AUR)
# --------------------------
# Upstream prebuilt repos only cover Debian/Ubuntu/Fedora/RHEL. On Arch we
# install the same openvpn3-linux project from the AUR (package: openvpn3).
# Docs: OpenVPN CloudConnexa "Install and Control the OpenVPN 3 Client" tutorial.

install_openvpn3_client() {
  if command -v openvpn3 &>/dev/null && pacman -Q openvpn3 &>/dev/null; then
    print_info_message "OpenVPN 3 client already installed: $(command -v openvpn3)"
  else
    print_action_message "Installing OpenVPN 3 Linux client from AUR (openvpn3)"
    if ! ensure_yay_installed; then
      print_error_message "yay is required to install openvpn3 from the AUR"
      return 1
    fi
    if ! ensure_yay_pkgs openvpn3; then
      print_error_message "Failed to install openvpn3 (AUR)"
      return 1
    fi
  fi

  # Package .install runs init-config, but re-run is safe and covers older partial installs
  if command -v openvpn3-admin &>/dev/null; then
    print_info_message "Ensuring OpenVPN 3 backend configs (openvpn3-admin init-config)"
    sudo openvpn3-admin init-config --write-configs 2>/dev/null \
      || print_warning_message "openvpn3-admin init-config failed — try: sudo openvpn3-admin init-config --write-configs"
    sudo systemctl reload dbus 2>/dev/null \
      || print_warning_message "Could not reload dbus after openvpn3 config"
  fi

  if command -v openvpn3 &>/dev/null; then
    print_success_message "openvpn3 available: $(command -v openvpn3)"
    print_info_message "Import CloudConnexa .ovpn (once), then connect:"
    print_info_message "  openvpn3 config-import --config /path/to/profile.ovpn --name CloudConnexa --persistent"
    print_info_message "  openvpn3 session-start --config CloudConnexa"
    print_info_message "  openvpn3 sessions-list"
    print_info_message "  openvpn3 session-manage --config CloudConnexa --disconnect"
  else
    print_warning_message "openvpn3 not on PATH after install — re-login or check: pacman -Ql openvpn3"
  fi
}

install_openvpn3_client || print_warning_message "OpenVPN 3 setup had errors (devcontainer VPN may be unavailable)"

# --------------------------
# Cursor: Dev Containers extension
# --------------------------

install_cursor_devcontainers_extension() {
  if ! command -v cursor &>/dev/null; then
    print_warning_message "cursor not on PATH — skip Dev Containers extension (install shared Cursor first)"
    return 0
  fi

  # VS Code / Cursor marketplace ID for Dev Containers
  local ext_id="ms-vscode-remote.remote-containers"
  if cursor --list-extensions 2>/dev/null | grep -qxF "$ext_id"; then
    print_info_message "Cursor extension already installed: $ext_id"
    return 0
  fi

  print_action_message "Installing Cursor extension: $ext_id"
  if cursor --install-extension "$ext_id" --force 2>/dev/null; then
    print_success_message "Installed $ext_id"
  else
    print_warning_message "Could not install $ext_id automatically — open Cursor Extensions and install 'Dev Containers'"
  fi
}

install_cursor_devcontainers_extension

# --------------------------
# Trust mkcert CA (user; never sudo on Linux)
# --------------------------

if command -v mkcert &>/dev/null; then
  print_info_message "Ensuring local mkcert CA is trusted (mkcert -install; no sudo)"
  # mkcert -install is idempotent; may prompt for password on some desktops
  if mkcert -install 2>/dev/null; then
    print_success_message "mkcert CA installed/trusted for this user"
  else
    print_warning_message "mkcert -install failed — run without sudo after bootstrap: mkcert -install"
  fi
  print_info_message "After cloning the platform devcontainer repo, generate Traefik certs"
  print_info_message "(see that repo's host TLS steps; paths are usually under .devcontainer/…/certs)"
else
  print_warning_message "mkcert missing after package install — skip CA trust"
fi

# --------------------------
# Host DNS for local *.test domains (container DNS on 127.0.0.1:5354)
# --------------------------

configure_test_domain_dns() {
  local conf_dir="/etc/systemd/resolved.conf.d"
  local conf_file="$conf_dir/dotfiles-arch-test.conf"
  local expected
  expected="[Resolve]
DNS=127.0.0.1:5354
Domains=~test
"

  if ! systemctl list-unit-files systemd-resolved.service &>/dev/null; then
    print_warning_message "systemd-resolved not available — configure *.test DNS manually (see devcontainer docs)"
    return 0
  fi

  if [[ -f "$conf_file" ]] && [[ "$(cat "$conf_file")" == "$expected" ]]; then
    print_info_message "DNS split for ~test already configured: $conf_file"
  else
    print_action_message "Writing $conf_file (route Domains=~test to 127.0.0.1:5354)"
    sudo mkdir -p "$conf_dir"
    printf '%s' "$expected" | sudo tee "$conf_file" >/dev/null
  fi

  if systemctl is-active --quiet systemd-resolved 2>/dev/null \
    || systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
    print_info_message "Restarting systemd-resolved to apply test domain config"
    sudo systemctl restart systemd-resolved \
      || print_warning_message "Could not restart systemd-resolved"
  else
    print_warning_message "systemd-resolved is not active/enabled — enable it or use NetworkManager DNS docs"
  fi
}

configure_test_domain_dns

# --------------------------
# inotify watches (large repo trees on Linux hosts)
# --------------------------

configure_inotify_watches() {
  local conf="/etc/sysctl.d/99-dotfiles-arch-inotify.conf"
  local key="fs.inotify.max_user_watches"
  local desired=524288
  local current

  current="$(sysctl -n "$key" 2>/dev/null || echo 0)"
  if [[ "$current" -ge "$desired" ]] && [[ -f "$conf" ]]; then
    print_info_message "$key already >= $desired ($current)"
    return 0
  fi

  print_action_message "Setting $key=$desired"
  printf '%s=%s\n' "$key" "$desired" | sudo tee "$conf" >/dev/null
  sudo sysctl --system >/dev/null 2>&1 \
    || sudo sysctl -p "$conf" >/dev/null 2>&1 \
    || print_warning_message "Could not apply sysctl live — reboot may be required"
}

configure_inotify_watches

# --------------------------
# Summary
# --------------------------

echo ""
print_info_message "Host prereqs for the platform devcontainer:"
print_info_message "  just=$(command -v just 2>/dev/null || echo missing)"
print_info_message "  mkcert=$(command -v mkcert 2>/dev/null || echo missing)"
print_info_message "  openvpn3=$(command -v openvpn3 2>/dev/null || echo missing)"
print_info_message "  gh=$(command -v gh 2>/dev/null || echo missing)"
print_info_message "  docker=$(command -v docker 2>/dev/null || echo missing)"
print_info_message "  dig=$(command -v dig 2>/dev/null || echo missing)"
print_info_message "Next: clone the platform devcontainer repo and Reopen in Container."
print_info_message "When the stack is up, verify DNS with dig @127.0.0.1 -p 5354 <name>.test +short"

print_tool_setup_complete "Devcontainer host prerequisites"
