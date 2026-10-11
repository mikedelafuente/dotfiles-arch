#!/usr/bin/env bash
# Shared desktop recipes. Pure selection consumes supplied ownership/version facts.
KEYMAPP_RELEASE_VERSION=1.3.7
KEYMAPP_RELEASE_SHA256=a87bc7083cd6461ba10e0da4b94f249a29100d712542d54498f01e947cf868fa

desktop_utility_selection() {
  local distro="$1" app="$2" source="$3" launcher="$4" alternate="$5" version="$6" package owner
  [[ "$alternate" == false && ( "$launcher" == '' || "$launcher" == owned ) ]] || return 1
  [[ "$source" != none || -z "$launcher" ]] || return 1
  [[ "$source" == none || "$launcher" == owned ]] || return 1
  case "$distro:$app:$source" in
    arch:tableplus:none|arch:tableplus:aur) package=tableplus; owner=aur ;;
    arch:postman:none|arch:postman:aur) package=postman-bin; owner=aur ;;
    arch:spotify:none|arch:spotify:aur) package=spotify; owner=aur ;;
    arch:obsidian:none|arch:obsidian:native) package=obsidian; owner=native ;;
    arch:obsidian:aur) package=obsidian-bin; owner=aur ;;
    arch:keymapp:none|arch:keymapp:aur) package=zsa-keymapp-bin; owner=aur ;;
    ubuntu:tableplus:none|ubuntu:tableplus:apt) package=tableplus; owner=apt ;;
    ubuntu:spotify:none|ubuntu:spotify:apt) package=spotify-client; owner=apt ;;
    ubuntu:postman:none|ubuntu:postman:snap|ubuntu:spotify:snap) package="$app"; owner=snap ;;
    ubuntu:postman:self)
      core_cli_version_at_least "$version" 9.13.0 || return 1
      package=postman; owner=self ;;
    ubuntu:obsidian:none|ubuntu:obsidian:release-deb) package=obsidian; owner='release-deb' ;;
    ubuntu:keymapp:none|ubuntu:keymapp:pinned-archive) package=keymapp; owner=pinned-archive ;;
    *) print_error_message "Required $app source/update-owner gap; existing installation preserved" >&2; return 1 ;;
  esac
  if [[ "$app" == postman && "$source" == snap ]]; then
    core_cli_version_at_least "$version" 9.13.0 || return 1
  fi
  if [[ "$app" == keymapp && "$source" == pinned-archive ]]; then
    core_cli_version_at_least "$version" 1.2.0 || return 1
  fi
  printf '%s %s\n' "$package" "$owner"
}

desktop_utility_obsidian_asset() {
  local metadata="$1" version tag fields url digest asset
  tag="$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$metadata")" || return 1
  [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
  version="${BASH_REMATCH[1]}"; asset="obsidian_${version}_amd64.deb"
  fields="$(jq -er --arg name "$asset" '[.assets[] | select(.name == $name)] | select(length == 1) | .[0] | [.browser_download_url,.digest] | @tsv' <<<"$metadata")" || return 1
  read -r url digest <<<"$fields"
  [[ "$url" == "https://github.com/obsidianmd/obsidian-releases/releases/download/$tag/$asset" \
    && "$digest" =~ ^sha256:([a-f0-9]{64})$ ]] || return 1
  printf '%s %s %s\n' "$version" "$url" "${BASH_REMATCH[1]}"
}

# Snap assertions retain vendor identity; never adopt a same-name unverified publisher.
desktop_utility_snap_id() {
  case "$1" in
    postman) echo fFcOtEEF4EdyYb95IUE5Isy28tICYMLf ;;
    spotify) echo pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7 ;;
    firefox) echo 3wdHCAVyZEmYsCMFDE9qt92UV8rC8Wdk ;;
    discord) echo qHVefGEBezeuCeSfTND40uoUD6GRw8BO ;;
    *) return 1 ;;
  esac
}

# Facts gathering does not launch apps. Package-owned launchers/desktop files and
# known vendor layouts are required; unknown/off-PATH installations fail closed.
desktop_utility_installed_selection() {
  local app="$1" recipe package owner source=none launcher='' alternate=false version='' path resolved snaps='' snap_installed=false flatpaks id info root
  recipe="$(desktop_utility_selection "$WORKSTATION_DISTRO" "$app" none '' false '')" || return 1
  read -r package owner <<<"$recipe"
  path="$(type -P "$app" || true)"
  [[ -z "$path" ]] || { resolved="$(readlink -f "$path")" || return 1; launcher=unknown; }
  if native_package_installed "$package"; then
    source="$owner"
    # These recipes own an asserted Snap or our pinned user tree, never a DEB
    # that happens to have the same name.
    [[ "$owner" != snap && "$owner" != pinned-archive ]] || source=unknown
    if [[ -n "$path" ]]; then
      if [[ "$WORKSTATION_DISTRO" == arch ]]; then
        [[ "$(pacman -Qqo "$resolved" 2>/dev/null)" == "$package" ]] && launcher=owned
      else
        dpkg-query -L "$package" | grep -Fx "$resolved" >/dev/null && launcher=owned
        version="$(dpkg-query -W -f='${Version}' "$package")" || return 1
      fi
    fi
  fi
  if [[ "$app" == obsidian && "$WORKSTATION_DISTRO" == arch ]] && native_package_installed obsidian-bin; then
    [[ "$source" == none ]] || alternate=true
    source=aur; package=obsidian-bin
    [[ -z "$path" || "$(pacman -Qqo "$resolved" 2>/dev/null)" != obsidian-bin ]] || launcher=owned
  fi
  if command -v snap &>/dev/null; then
    snaps="$(snap list --unicode=never 2>/dev/null)" || return 1
    if awk '{print $1}' <<<"$snaps" | grep -Fxq "$app"; then snap_installed=true; fi
  fi
  if [[ "$snap_installed" == true ]]; then
    [[ "$source" == none ]] || alternate=true
    [[ "$app" == postman || "$app" == spotify ]] || { print_error_message "Unselected $app Snap; preserved" >&2; return 1; }
    id="$(desktop_utility_snap_id "$app")" || return 1
    info="$(snap info --unicode=never "$app")" || return 1
    [[ "$(awk '$1 == "snap-id:" {print $2}' <<<"$info")" == "$id" ]] || return 1
    source=snap
    if [[ "$path" == "/snap/bin/$app" || "$path" == "/var/lib/snapd/snap/bin/$app" \
      || ( -L "$path" && "$(readlink "$path")" == "/snap/bin/$app" ) \
      || ( -z "$path" && -x "/snap/bin/$app" ) ]]; then launcher=owned; fi
    version="$(awk -v app="$app" '$1 == app {print $2}' <<<"$snaps")"
    [[ "$(awk -v app="$app" '$1 == app {print $4}' <<<"$snaps")" == */stable ]] || return 1
  fi
  if command -v flatpak &>/dev/null; then
    flatpaks="$(flatpak list --app --columns=application)" || return 1
    case "$app" in
      tableplus) id=com.tableplus.TablePlus ;; postman) id=com.getpostman.Postman ;;
      spotify) id=com.spotify.Client ;; obsidian) id=md.obsidian.Obsidian ;; keymapp) id=io.zsa.Keymapp ;;
    esac
    if grep -Fxq "$id" <<<"$flatpaks"; then alternate=true; fi
  fi
  # Retain the official writable user archive's genuine Postman updater (9.13+).
  if [[ "$app" == postman && "$WORKSTATION_DISTRO" == ubuntu ]]; then
    for root in "$USER_HOME_DIR/.local/share/Postman" "$USER_HOME_DIR/Postman" /opt/Postman; do
      [[ -e "$root" || -L "$root" ]] || continue
      if [[ "$source" == none && -n "$path" && "$resolved" == "$root/app/Postman" \
        && ! -L "$root" && -O "$root" && -w "$root" && -r "$root/app/resources/app/package.json" ]]; then
        version="$(jq -er 'select(.name == "postman") | .version' "$root/app/resources/app/package.json")" || return 1
        source=self; launcher=owned
      else
        alternate=true
      fi
    done
  fi
  # Off-PATH vendor trees are sources too. Do not duplicate them with packages.
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    local candidate
    case "$app" in
      obsidian) for candidate in "$USER_HOME_DIR/.local/share/obsidian" "$USER_HOME_DIR/.local/obsidian"; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] || alternate=true
      done ;;
      keymapp) for candidate in "$USER_HOME_DIR/.local/share/keymapp" "$USER_HOME_DIR/.local/keymapp"; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] || alternate=true
      done ;;
    esac
  fi
  root="$USER_HOME_DIR/.local/share/dotfiles-arch/keymapp"
  if [[ "$app" == keymapp && "$WORKSTATION_DISTRO" == ubuntu && ( -e "$root" || -L "$root" ) ]]; then
    version="$(readlink "$root/current")" || return 1
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$source" == none && ! -L "$root" && -O "$root" \
      && -L "$path" && "$(readlink "$path")" == "$root/current/keymapp" \
      && "$resolved" == "$root/$version/keymapp" && ! -L "$root/$version" \
      && -r "$root/$version/.dfa-sha256" && "$(cat "$root/$version/.dfa-sha256")" =~ ^[a-f0-9]{64}$ \
      && -r "$root/$version/.dfa-binary-sha256" \
      && "$(sha256sum "$resolved" | awk '{print $1}')" == "$(cat "$root/$version/.dfa-binary-sha256")" ]] || return 1
    source=pinned-archive; launcher=owned
  fi
  if [[ "$WORKSTATION_DISTRO" == ubuntu && ( "$source" == apt || "$app" == tableplus || "$app" == spotify || "$app" == obsidian ) ]]; then
    local apt_source
    if [[ "$app" == tableplus || "$app" == spotify ]]; then
      apt_source="$(work_app_apt_source "$app")" || return 1
      [[ "$source" != apt || -n "$apt_source" ]] || return 1
      [[ "$source" != snap || -z "$apt_source" ]] || alternate=true
    elif [[ "$app" == obsidian ]]; then
      # There is no official Obsidian APT repository. Preserve alternate owners.
      if grep -RqiE 'obsidian' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then alternate=true; fi
    fi
  fi
  desktop_utility_selection "$WORKSTATION_DISTRO" "$app" "$source" "$launcher" "$alternate" "$version"
}

install_obsidian_deb() (
  local stage metadata release version url digest installed holds
  holds="$(apt-mark showhold)" || return 1
  if grep -Fxq obsidian <<<"$holds"; then
    print_info_message 'Obsidian installer update policy-deferred: APT hold retained'; return 0
  fi
  ensure_native_pkgs curl ca-certificates jq || return 1
  metadata="$(curl --proto '=https' --tlsv1.2 -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest)" || return 1
  release="$(desktop_utility_obsidian_asset "$metadata")" || return 1
  read -r version url digest <<<"$release"
  if native_package_installed obsidian; then
    installed="$(dpkg-query -W -f='${Version}' obsidian)" || return 1
    if dpkg --compare-versions "$version" gt "$installed"; then :; else
      local rc=$?; [[ "$rc" == 1 ]] && return 0; return "$rc"
    fi
  fi
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$stage/obsidian.deb" || return 1
  printf '%s  %s\n' "$digest" "$stage/obsidian.deb" | sha256sum -c - || return 1
  [[ "$(dpkg-deb -f "$stage/obsidian.deb" Package)" == obsidian \
    && "$(dpkg-deb -f "$stage/obsidian.deb" Architecture)" == amd64 \
    && "$(dpkg-deb -f "$stage/obsidian.deb" Version)" == "$version" ]] || return 1
  chmod 755 "$stage" || return 1
  chmod 644 "$stage/obsidian.deb" || return 1
  sudo apt-get install --yes --no-remove "$stage/obsidian.deb" || return 1
)

# Vendor publishes only a mutable URL: reviewed 1.3.7 pin from the IoC-inspected
# AUR recipe, matched against official bytes. Upstream changes require pin review.
install_keymapp_archive() (
  local stage root="$USER_HOME_DIR/.local/share/dotfiles-arch/keymapp" digest="$KEYMAPP_RELEASE_SHA256" version="$KEYMAPP_RELEASE_VERSION" target swap=''
  [[ "$EUID" != 0 && -z "${SUDO_USER:-}" ]] || {
    print_error_message 'Run Keymapp setup/update as the workstation user, without sudo' >&2; return 1;
  }
  core_cli_link_allowed "$root/current/keymapp" "$USER_HOME_DIR/.local/bin/keymapp" || return 1
  core_cli_link_allowed "$root/current/keymapp" "$root/.dfa-preflight" || return 1
  [[ ! -e "$root/current" || -L "$root/current" ]] || return 1
  ensure_native_pkgs curl ca-certificates python3 libusb-1.0-0 libgtk-3-0t64 libwebkit2gtk-4.1-0 || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"; [[ -z "$swap" ]] || rm -rf "$swap"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL https://oryx.nyc3.cdn.digitaloceanspaces.com/keymapp/keymapp-latest.tar.gz -o "$stage/keymapp.tar.gz" || return 1
  printf '%s  %s\n' "$digest" "$stage/keymapp.tar.gz" | sha256sum -c - || {
    print_error_message 'Required Keymapp pin refresh: vendor archive changed; working installation preserved'; return 1;
  }
  python3 - "$stage/keymapp.tar.gz" "$stage" <<'PY' || return 1
import sys, tarfile
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    members = archive.getmembers()
    if {m.name for m in members} != {'keymapp', 'icon.png'} or len(members) != 2 or any(not m.isfile() for m in members):
        raise ValueError('Unexpected Keymapp archive members')
    archive.extractall(sys.argv[2], members=members, filter='data')
PY
  [[ "$(od -An -tx1 -N5 "$stage/keymapp" | tr -d ' \n')" == 7f454c4602 \
    && "$(od -An -tx1 -j18 -N2 "$stage/keymapp" | tr -d ' \n')" == 3e00 ]] || return 1
  target="$root/$version"
  if [[ -e "$target" || -L "$target" ]]; then
    [[ ! -L "$target" && ! -L "$target/keymapp" && ! -L "$target/icon.png" \
      && -r "$target/.dfa-sha256" && "$(cat "$target/.dfa-sha256")" == "$digest" \
      && -r "$target/.dfa-binary-sha256" \
      && "$(cat "$target/.dfa-binary-sha256")" == "$(sha256sum "$stage/keymapp" | awk '{print $1}')" ]] \
      && cmp -s "$stage/keymapp" "$target/keymapp" && cmp -s "$stage/icon.png" "$target/icon.png" || return 1
  else
    mkdir -p "$root" || return 1
    chmod 755 "$stage/keymapp" || return 1
    printf '%s\n' "$digest" >"$stage/.dfa-sha256" || return 1
    sha256sum "$stage/keymapp" | awk '{print $1}' >"$stage/.dfa-binary-sha256" || return 1
    mkdir "$stage/release" || return 1
    mv "$stage/keymapp" "$stage/icon.png" "$stage/.dfa-sha256" "$stage/.dfa-binary-sha256" "$stage/release/" || return 1
    mv -T "$stage/release" "$target" || return 1
  fi
  swap="$(mktemp -d "$root/.link.XXXXXX")" || return 1
  ln -s "$version" "$swap/current" || return 1
  mv -Tf "$swap/current" "$root/current" || return 1
  link_core_cli_config "$root/current/keymapp" "$USER_HOME_DIR/.local/bin/keymapp" || return 1
)

desktop_utility_vendor_desktop() {
  case "$1" in
    tableplus) printf '%s\n' /opt/tableplus/tableplus.desktop ;;
    spotify) printf '%s\n' /usr/share/spotify/spotify.desktop ;;
    *) return 1 ;;
  esac
}

ensure_desktop_utility() {
  local app="$1" selection package owner binary desktop root target
  [[ "$app" != keymapp || ( "$EUID" != 0 && -z "${SUDO_USER:-}" ) ]] || {
    print_error_message 'Run Keymapp setup/update as the workstation user, without sudo' >&2; return 1;
  }
  selection="$(desktop_utility_installed_selection "$app")" || {
    print_error_message "Required $app source/launcher/update-owner gap; preserved"; return 1;
  }
  read -r package owner <<<"$selection"
  if [[ "$WORKSTATION_DISTRO:$owner" == ubuntu:apt && ( "$app" == tableplus || "$app" == spotify ) ]]; then
    desktop="$(desktop_utility_vendor_desktop "$app")" || return 1
    core_cli_link_allowed "$desktop" "$USER_HOME_DIR/.local/share/applications/$app.desktop" || {
      print_error_message "$app desktop override conflict; preserved"
      return 1
    }
  fi
  case "$owner" in
    apt) ensure_work_app "$app" || return 1 ;;
    native) ensure_native_pkgs "$package" || return 1 ;;
    aur) ensure_yay_installed && ensure_yay_pkgs "$package" || return 1 ;;
    snap)
      if ! type -P "$app" &>/dev/null; then
        [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* || ":$PATH:" == *":/snap/bin:"* ]] || return 1
        core_cli_link_allowed "/snap/bin/$app" "$USER_HOME_DIR/.local/bin/$app" || return 1
      fi
      if ! command -v snap &>/dev/null; then ensure_native_pkgs snapd || return 1; fi
      if ! snap list --unicode=never "$app" &>/dev/null; then
        [[ "$(snap info --unicode=never "$app" | awk '$1 == "snap-id:" {print $2}')" == "$(desktop_utility_snap_id "$app")" ]] || return 1
        sudo snap install "$app" --channel=latest/stable || return 1
      fi
      if ! type -P "$app" &>/dev/null; then
        [[ -x "/snap/bin/$app" && ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
        link_core_cli_config "/snap/bin/$app" "$USER_HOME_DIR/.local/bin/$app" || return 1
      fi ;;
    release-deb) if ! native_package_installed obsidian; then install_obsidian_deb || return 1; fi ;;
    pinned-archive)
      root="$USER_HOME_DIR/.local/share/dotfiles-arch/keymapp"
      binary="$root/current/keymapp"
      core_cli_link_allowed "$binary" "$USER_HOME_DIR/.local/bin/keymapp" || return 1
      desktop="$USER_HOME_DIR/.local/share/applications/dfa-keymapp.desktop"
      [[ ! -L "$desktop" && ( ! -e "$desktop" || -f "$desktop" ) ]] || return 1
      if [[ -e "$desktop" ]]; then
        grep -Fxq "Exec=\"$binary\"" "$desktop" || { print_error_message 'Keymapp desktop conflict; preserved'; return 1; }
      else
        target="$(dirname "$desktop")"
        core_cli_link_allowed "$binary" "$target/.dfa-keymapp-preflight" || return 1
      fi
      [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
      install_keymapp_archive || return 1
      if [[ ! -e "$desktop" ]]; then
        mkdir -p "$(dirname "$desktop")" || return 1
        printf '[Desktop Entry]\nType=Application\nName=Keymapp\nExec="%s"\nIcon=%s\nTerminal=false\nCategories=Settings;HardwareSettings;\n' "$binary" "$root/current/icon.png" >"$desktop" || return 1
      fi ;;
    self)
      binary="$(readlink -f "$(type -P postman)")" || return 1
      desktop="$USER_HOME_DIR/.local/share/applications/dfa-postman.desktop"
      [[ ! -L "$desktop" && ( ! -e "$desktop" || -f "$desktop" ) ]] || return 1
      if [[ -e "$desktop" ]]; then
        grep -Fxq "Exec=\"$binary\" %U" "$desktop" || return 1
      else
        core_cli_link_allowed "$binary" "$(dirname "$desktop")/.dfa-postman-preflight" || return 1
        mkdir -p "$(dirname "$desktop")" || return 1
        printf '[Desktop Entry]\nType=Application\nName=Postman\nExec="%s" %%U\nTerminal=false\nCategories=Development;\n' "$binary" >"$desktop" || return 1
      fi
      print_info_message 'Postman archive retained; keep in-app updates enabled and restart to apply them' ;;
    *) return 1 ;;
  esac
  desktop_utility_installed_selection "$app" >/dev/null || return 1
  # A package-provided desktop launcher must exist; never fabricate an entry for
  # a broken package or silently override a user entry.
  if [[ "$owner" == native || "$owner" == aur || "$owner" == apt || "$owner" == release-deb ]]; then
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then
      pacman -Qlq "$package" | grep -E '^/usr/share/applications/[^/]+\.desktop$' >/dev/null || return 1
    else
      if [[ "$app" == tableplus || "$app" == spotify ]]; then
        desktop="$(desktop_utility_vendor_desktop "$app")" || return 1
        dpkg-query -L "$package" | grep -Fx "$desktop" >/dev/null || return 1
        [[ -f "$desktop" ]] || return 1
        link_core_cli_config "$desktop" "$USER_HOME_DIR/.local/share/applications/$app.desktop" || return 1
      else
        dpkg-query -L "$package" | grep -E '^/usr/share/applications/[^/]+\.desktop$' >/dev/null || return 1
      fi
    fi
  elif [[ "$owner" == snap ]]; then
    compgen -G "/var/lib/snapd/desktop/applications/${app}_*.desktop" >/dev/null || return 1
  fi
  print_info_message "$app update owner: $owner; desktop, sandbox and update runtime unverified"
}

# Check all installed selected sources before the native transaction. Snap owns
# automatic updates/holds; user archives own in-app updates, not APT refreshes.
check_desktop_utility_owners() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package selection path snaps='' root owner sources key stage
  if command -v snap &>/dev/null; then snaps="$(snap list --unicode=never 2>/dev/null)" || return 1; fi
  for app in tableplus postman spotify obsidian keymapp; do
    selection="$(desktop_utility_selection ubuntu "$app" none '' false '')" || return 1
    read -r package _ <<<"$selection"
    path="$(type -P "$app" || true)"
    root="$USER_HOME_DIR/.local/share/dotfiles-arch/$app"
    if native_package_installed "$package" || [[ -n "$path" || -e "$root" || -L "$root" ]] \
      || awk '{print $1}' <<<"$snaps" | grep -Fxq "$app"; then
      selection="$(desktop_utility_installed_selection "$app")" || return 1
      read -r _ owner <<<"$selection"
      if [[ "$owner" == apt ]]; then
        sources="$(work_app_apt_source "$app")" || return 1
        read -r _ key <<<"$sources"
        stage="$(mktemp -d)" || return 1
        if ! stage_work_app_key "$app" "$stage" "$key"; then rm -rf "$stage"; return 1; fi
        rm -rf "$stage"
      fi
    fi
  done
}

check_desktop_utility_candidates() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package
  for app in tableplus spotify; do
    [[ "$app" != spotify ]] && package=tableplus || package=spotify-client
    native_package_installed "$package" || continue
    work_app_apt_candidate "$app" "$(apt-cache policy "$package")" >/dev/null || return 1
  done
}

refresh_desktop_utilities() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  check_desktop_utility_owners || return 1
  if native_package_installed obsidian; then install_obsidian_deb || return 1; fi
  if [[ -e "$USER_HOME_DIR/.local/share/dotfiles-arch/keymapp" ]]; then install_keymapp_archive || return 1; fi
  print_info_message 'Desktop utilities: vendor APT and verified installer/archive owners refreshed; Snap automatic updates and Postman in-app settings/holds retained'
}
