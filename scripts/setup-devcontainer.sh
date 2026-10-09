#!/bin/bash
# Devcontainer host tools, user CA trust, split DNS and watcher limits.
# Safe to rerun on rolling Arch / Ubuntu 26.04. No VPN/cluster is started.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# mkcert must own its CA as the workstation user, even when sudo is available.
if [[ "$EUID" == 0 ]]; then
  print_error_message 'Run setup-devcontainer.sh as your workstation user, without sudo (user-owned mkcert CA)'
  exit 1
fi
print_tool_setup_start "Devcontainer host prerequisites"
FAILED=0

for app in just mkcert dig nss; do
  ensure_devcontainer_tool "$app" || exit 1
done
# Recheck the complete shared stack even when docker/gh are already on PATH.
bash "$DF_SCRIPT_DIR/setup-docker.sh" || exit 1
ensure_core_cli github-cli || exit 1

install_openvpn3_client() {
  local admin client=false backend=true service
  ensure_devcontainer_tool openvpn3 || return 1
  case "$WORKSTATION_DISTRO" in
    arch) admin=/usr/bin/openvpn3-admin ;;
    ubuntu) admin=/usr/sbin/openvpn3-admin ;;
  esac
  [[ -x /usr/bin/openvpn3 ]] && client=true
  for service in backends configuration sessions netcfg; do
    [[ -r "/usr/share/dbus-1/system-services/net.openvpn.v3.$service.service" ]] || backend=false
  done
  local admin_available=false
  [[ -x "$admin" ]] && admin_available=true
  openvpn3_capabilities_complete "$client" "$admin_available" || return 1
  if [[ "$backend" != true ]]; then
    print_error_message 'OpenVPN3 D-Bus backend registration gap; VPN unavailable'
    return 1
  fi
  sudo "$admin" init-config --write-configs || return 1
  sudo systemctl reload dbus.service || return 1
  print_info_message 'OpenVPN3 client/backend files configured; VPN connection, DNS integration and DCO unverified'
  print_info_message 'Import your profile with openvpn3 config-import --config /path/to/profile.ovpn --name CloudConnexa --persistent'
}
install_openvpn3_client || {
  print_error_message 'OpenVPN3 setup incomplete; devcontainer VPN may be unavailable'
  FAILED=1
}

# Never sudo mkcert: the CA and private key belong to this user. mkcert itself
# may request sudo for the system trust store, retaining the existing trust intent.
if ! mkcert -install; then
  print_error_message 'CA trust incomplete; rerun mkcert -install as your workstation user'
  FAILED=1
fi

configure_test_domain_dns() {
  local conf_dir=/etc/systemd/resolved.conf.d
  local conf_file="$conf_dir/dotfiles-arch-test.conf" loaded active=false resolver expected
  loaded="$(systemctl show -p LoadState --value systemd-resolved.service)" || return 1
  systemctl is-active --quiet systemd-resolved.service && active=true
  resolver="$(readlink -f /etc/resolv.conf || true)"
  devcontainer_dns_ready "$loaded" "$active" "$resolver" || return 1
  expected='[Resolve]
DNS=127.0.0.1:5354
Domains=~test'
  [[ ! -L "$conf_file" ]] || { print_error_message "DNS config symlink conflict: $conf_file; preserved"; return 1; }
  if [[ ! -f "$conf_file" || "$(cat "$conf_file")" != "$expected" ]]; then
    sudo mkdir -p "$conf_dir" || return 1
    printf '%s\n' "$expected" | sudo tee "$conf_file" >/dev/null || return 1
  fi
  # Retry application on reruns too: a prior write may have succeeded before restart failed.
  sudo systemctl restart systemd-resolved.service || return 1
  print_info_message "Split DNS configured in $conf_file; application DNS behavior unverified"
}
configure_test_domain_dns || {
  print_error_message 'Split DNS incomplete; resolve host DNS policy before using *.test'
  FAILED=1
}

configure_inotify_watches() {
  local conf=/etc/sysctl.d/99-dotfiles-arch-inotify.conf current desired expected
  current="$(sysctl -n fs.inotify.max_user_watches)" || return 1
  desired="$(devcontainer_watch_limit "$current")" || return 1
  expected="fs.inotify.max_user_watches=$desired"
  [[ ! -L "$conf" ]] || { print_error_message "Watcher config symlink conflict: $conf; preserved"; return 1; }
  if [[ ! -f "$conf" || "$(cat "$conf")" != "$expected" ]]; then
    printf '%s\n' "$expected" | sudo tee "$conf" >/dev/null || return 1
  fi
  if [[ "$current" -lt "$desired" ]]; then
    sudo sysctl -p "$conf" || return 1
  fi
}
configure_inotify_watches || { print_error_message 'Watcher limit configuration incomplete'; FAILED=1; }

if [[ "$FAILED" != 0 ]]; then
  print_error_message 'Devcontainer host setup finished with gaps; see errors above'
  exit 1
fi
print_info_message 'Next: generate project Traefik certs after clone, then Reopen in Container'
print_info_message 'With the stack running, check DNS: dig @127.0.0.1 -p 5354 <name>.test +short'
print_info_message 'Installation/service/certificate/VPN/networking runtime behavior has not been validated by repository tests'
print_tool_setup_complete "Devcontainer host prerequisites"
