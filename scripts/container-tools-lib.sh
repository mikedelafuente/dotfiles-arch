#!/usr/bin/env bash
# Container source decisions consume supplied facts; setup gathers facts separately.
docker_package_selection() {
  local distro="$1" installed="$2" launcher="$3" pkg engine
  local -a selected
  case "$distro" in
    arch) selected=(docker docker-compose docker-buildx); engine=docker ;;
    ubuntu) selected=(docker.io docker-compose-v2 docker-buildx); engine=docker.io ;;
    *) return 1 ;;
  esac
  for pkg in $installed; do
    case "$pkg" in
      docker|docker.io|docker-ce*|docker-compose*|docker-buildx*|docker-desktop|docker-bin|docker-git|docker-static|containerd.io|containerd-git|runc-git|podman-docker|moby-*)
        if [[ " ${selected[*]} " != *" $pkg "* ]]; then
          print_error_message "Docker source conflict: $pkg; existing installation preserved" >&2
          return 1
        fi ;;
    esac
  done
  if [[ -n "$launcher" && ( "$launcher" != /usr/bin/docker || " $installed " != *" $engine "* ) ]]; then
    print_error_message "Docker launcher has unknown/conflicting ownership: $launcher; preserved" >&2
    return 1
  fi
  printf '%s\n' "${selected[*]}"
}

# Package ownership plus offline command capability is required for every component.
docker_components_complete() {
  local engine="$1" compose="$2" buildx="$3" missing=()
  [[ "$engine" == true ]] || missing+=(Engine)
  [[ "$compose" == true ]] || missing+=(Compose)
  [[ "$buildx" == true ]] || missing+=(Buildx)
  [[ ${#missing[@]} -gt 0 ]] || return 0
  print_error_message "Incomplete Docker: ${missing[*]} unavailable; daemon/networking readiness unverified" >&2
  return 1
}

installed_container_packages() {
  case "$WORKSTATION_DISTRO" in
    arch) pacman -Qq ;;
    ubuntu) dpkg-query -W -f='${db:Status-Eflag} ${db:Status-Status} ${binary:Package}\n' \
      | awk '$1 == "ok" && $2 == "installed" {sub(/:.*/, "", $3); print $3}' ;;
    *) return 1 ;;
  esac
}

# Refuse plugin overrides rather than claiming native package presence proves ownership.
docker_plugins_allowed() {
  local config="$1" dir plugin
  shift
  if [[ -e "$config/config.json" ]]; then
    jq -e '(.cliPluginsExtraDirs // []) == []' "$config/config.json" >/dev/null || {
      print_error_message 'Docker extra plugin directories/config conflict; preserved'; return 1;
    }
  fi
  for dir in "$config/cli-plugins" "$@"; do
    for plugin in docker-compose docker-buildx; do
      if [[ -e "$dir/$plugin" || -L "$dir/$plugin" ]]; then
        print_error_message "Docker plugin override: $dir/$plugin; preserved"; return 1
      fi
    done
  done
}

docker_native_plugins_owned() {
  local compose_package="$1" buildx_package="$2" dir plugin package owned
  for dir in /usr/lib/docker/cli-plugins /usr/libexec/docker/cli-plugins; do
    for plugin in docker-compose docker-buildx; do
      [[ -e "$dir/$plugin" || -L "$dir/$plugin" ]] || continue
      package="$buildx_package"
      [[ "$plugin" != docker-compose ]] || package="$compose_package"
      case "$WORKSTATION_DISTRO" in
        arch) owned="$(pacman -Qoq "$dir/$plugin" 2>/dev/null)" || return 1 ;;
        ubuntu) owned="$(dpkg-query -S "$dir/$plugin" 2>/dev/null)" || return 1; owned="${owned%%: /*}" ;;
      esac
      [[ "$owned" == "$package" ]] || {
        print_error_message "Docker plugin ownership conflict: $dir/$plugin; preserved"; return 1;
      }
    done
  done
}

ensure_docker_components() {
  local facts launcher selection engine=false compose=false buildx=false
  local -a packages
  facts="$(installed_container_packages)" || return 1
  facts="${facts//$'\n'/ }"
  launcher="$(type -P docker || true)"
  [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")"
  selection="$(docker_package_selection "$WORKSTATION_DISTRO" "$facts" "$launcher")" || return 1
  read -r -a packages <<<"$selection"
  if ! native_package_installed "${packages[0]}" \
    && { [[ -e /usr/bin/docker || -L /usr/bin/docker || -e /usr/bin/dockerd || -L /usr/bin/dockerd ]]; }; then
    print_error_message 'Unowned Docker files; existing installation preserved'; return 1
  fi
  if [[ -e "$USER_HOME_DIR/.config/systemd/user/docker.service" || -L "$USER_HOME_DIR/.config/systemd/user/docker.service" ]]; then
    print_error_message 'User/rootless Docker service conflict; preserved'; return 1
  fi
  # jq is shared CLI tooling, required to inspect Docker plugin configuration.
  ensure_core_cli jq || return 1
  docker_plugins_allowed "${DOCKER_CONFIG:-$USER_HOME_DIR/.docker}" \
    /usr/local/lib/docker/cli-plugins /usr/local/libexec/docker/cli-plugins || return 1
  docker_native_plugins_owned "${packages[1]}" "${packages[2]}" || {
    print_error_message 'Docker plugin source conflict; existing installation preserved'; return 1;
  }
  ensure_native_pkgs "${packages[@]}" || return 1
  docker_native_plugins_owned "${packages[1]}" "${packages[2]}" || return 1
  hash -r
  [[ "$(readlink -f "$(type -P docker || true)")" == /usr/bin/docker ]] || return 1
  native_package_installed "${packages[0]}" && /usr/bin/docker --version >/dev/null && engine=true
  native_package_installed "${packages[1]}" && /usr/bin/docker compose version >/dev/null && compose=true
  native_package_installed "${packages[2]}" && /usr/bin/docker buildx version >/dev/null && buildx=true
  docker_components_complete "$engine" "$compose" "$buildx"
}

# Explicit devcontainer host mappings. NSS means certutil, not name-service NSS.
devcontainer_recipe() {
  case "$1:$2" in
    arch:just|ubuntu:just) echo 'just just native' ;;
    arch:mkcert|ubuntu:mkcert) echo 'mkcert mkcert native' ;;
    arch:dig) echo 'bind dig native' ;;
    ubuntu:dig) echo 'bind9-dnsutils dig native' ;;
    arch:nss) echo 'nss certutil native' ;;
    ubuntu:nss) echo 'libnss3-tools certutil native' ;;
    arch:openvpn3) echo 'openvpn3 openvpn3 aur' ;;
    ubuntu:openvpn3) echo 'openvpn3-client openvpn3 native' ;;
    *) return 1 ;;
  esac
}

ensure_devcontainer_tool() {
  local app="$1" recipe package command owner installed=false launcher expected
  recipe="$(devcontainer_recipe "$WORKSTATION_DISTRO" "$app")" || return 1
  read -r package command owner <<<"$recipe"
  native_package_installed "$package" && installed=true
  expected="$(readlink -m "/usr/bin/$command")"
  launcher="$(type -P "$command" || true)"
  [[ -z "$launcher" ]] || launcher="$(readlink -f "$launcher")"
  if ! core_cli_source_allowed "$installed" "$launcher" "$expected" \
    || { [[ "$installed" == false && ( -e "$expected" || -L "$expected" ) ]]; }; then
    print_error_message "Source conflict: $app is not owned by $package; preserved"; return 1
  fi
  if [[ "$owner" == aur ]]; then
    ensure_yay_installed && ensure_yay_pkgs "$package" || return 1
  else
    ensure_native_pkgs "$package" || return 1
  fi
  if ! native_package_installed "$package" || [[ ! -x "$expected" ]]; then
    print_error_message "Missing $app capability after installing $package"
    return 1
  fi
}

# A client alone does not prove its privilege-separated D-Bus backend is available.
openvpn3_capabilities_complete() {
  [[ "$1" == true && "$2" == true ]] || {
    print_error_message 'OpenVPN3 client/admin capability gap; VPN unavailable, connection/DCO unverified' >&2
    return 1
  }
}

# Never lower a host's existing watcher limit to the profile minimum.
devcontainer_watch_limit() {
  [[ "$1" =~ ^[0-9]{1,9}$ ]] || return 1
  if ((10#$1 > 524288)); then printf '%s\n' "$((10#$1))"; else echo 524288; fi
}

# A drop-in alone does not route application DNS through the local stub.
devcontainer_dns_ready() {
  [[ "$1" == loaded && "$2" == true && "$3" == /run/systemd/resolve/stub-resolv.conf ]] || {
    print_error_message 'Split DNS requires active systemd-resolved and /etc/resolv.conf using its stub; configure the host resolver explicitly' >&2
    return 1
  }
}

# A standalone DEB is not APT-updatable unless a repository publishes its candidate.
kubernetes_native_update_owner() {
  local distro="$1" policy="$2"
  case "$distro" in
    arch) echo native; return 0 ;;
    ubuntu) ;;
    *) return 1 ;;
  esac
  if awk '
    $1 == "Candidate:" {candidate=$2}
    $1 == "***" {selected=($2 == candidate); next}
    NF == 2 && $2 ~ /^[0-9]+$/ {selected=($1 == candidate); next}
    selected && $2 ~ /^(https?:\/\/|file:)/ {found=1}
    END {exit !found}
  ' <<<"$policy"; then
    echo native
  else
    print_error_message 'Kubernetes package has no repository update owner; standalone DEB preserved, resolve its source explicitly' >&2
    return 1
  fi
}

ensure_kubernetes_tool() {
  local app="$1" policy
  case "$app" in minikube|kubectl|k9s) ;; *) return 1 ;; esac
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]] && native_package_installed "$app"; then
    policy="$(LC_ALL=C apt-cache policy "$app")" || return 1
    kubernetes_native_update_owner "$WORKSTATION_DISTRO" "$policy" >/dev/null || return 1
  fi
  ensure_editor_tool "$app"
}
