#!/usr/bin/env bash
# Official bootstrap inspected without execution; Discord's Rust updater owns later releases.
DISCORD_BOOTSTRAP_VERSION=1.0.161
DISCORD_BOOTSTRAP_SHA256=1a486a0cd0dc0e79b952b14dd5e361a8614dc28d1d371cd00ebf37a2ad0ce63d

# Supplied-fact seam: distro, app, source, launcher owner, duplicate, package version.
personal_app_selection() {
  local distro="$1" app="$2" source="$3" launcher="$4" alternate="$5" version="$6" package owner
  [[ "$alternate" == false && ( -z "$launcher" || "$launcher" == owned ) ]] || return 1
  [[ "$source" != none || -z "$launcher" ]] || return 1
  [[ "$source" == none || "$launcher" == owned ]] || return 1
  case "$distro:$app:$source" in
    arch:steam:none|arch:steam:native) package=steam; owner=native ;;
    arch:discord:none|arch:discord:native) package=discord; owner=native ;;
    arch:firefox:none|arch:firefox:native) package=firefox; owner=native ;;
    arch:mullvad:none|arch:mullvad:aur) package=mullvad-vpn-bin; owner=aur ;;
    ubuntu:steam:none|ubuntu:steam:native) package=steam-installer; owner=native ;;
    ubuntu:discord:none|ubuntu:discord:self-deb)
      [[ "$source" == none ]] || core_cli_version_at_least "$version" 1.0.0 || return 1
      package=discord; owner=self-deb ;;
    ubuntu:discord:snap|ubuntu:firefox:none|ubuntu:firefox:snap) package="$app"; owner=snap ;;
    ubuntu:firefox:apt) package=firefox; owner=apt ;;
    ubuntu:mullvad:none|ubuntu:mullvad:apt) package=mullvad-vpn; owner=apt ;;
    *) print_error_message "Required $app source/update-owner conflict; existing app preserved" >&2; return 1 ;;
  esac
  printf '%s %s\n' "$package" "$owner"
}

# Work wins for additive profiles. The exported Snap desktop ID differs from DEB.
personal_browser_selection() {
  local profiles="$1" chrome="$2" firefox_desktop="$3"
  if [[ " $profiles " == *' work '* ]]; then
    [[ "$chrome" == google-chrome || "$chrome" == google-chrome-stable ]] || return 1
    printf 'google-chrome.desktop %s\n' "$chrome"
  elif [[ " $profiles " == *' personal '* || -z "$chrome" ]]; then
    [[ "$firefox_desktop" == firefox.desktop || "$firefox_desktop" == firefox_firefox.desktop ]] || return 1
    printf '%s firefox\n' "$firefox_desktop"
  else
    [[ "$chrome" == google-chrome || "$chrome" == google-chrome-stable ]] || return 1
    printf 'google-chrome.desktop %s\n' "$chrome"
  fi
}

personal_app_installed_selection() {
  local app="$1" package owner recipe source=none launcher='' alternate=false path resolved version='' snaps='' info id flatpaks sources root
  recipe="$(personal_app_selection "$WORKSTATION_DISTRO" "$app" none '' false '')" || return 1
  read -r package owner <<<"$recipe"
  path="$(type -P "$app" || true)"
  [[ -z "$path" ]] || { resolved="$(readlink -f "$path")" || return 1; launcher=unknown; }
  if native_package_installed "$package"; then
    source="$owner"
    if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
      version="$(dpkg-query -W -f='${Version}' "$package")" || return 1
      # Ubuntu's Firefox DEB is a Snap bootstrap, not a second browser.
      if [[ "$app" == firefox && "$version" == *snap* ]]; then
        source=none
        [[ "$path" != /usr/bin/firefox ]] || launcher=''
      else
        [[ "$app" != firefox ]] || source=apt
        if [[ -n "$path" ]] && dpkg-query -L "$package" | grep -Fx "$resolved" >/dev/null; then launcher=owned; fi
      fi
    elif [[ -n "$path" && "$(pacman -Qqo "$resolved" 2>/dev/null)" == "$package" ]]; then launcher=owned; fi
  fi
  if command -v snap &>/dev/null; then
    snaps="$(snap list --unicode=never 2>/dev/null)" || return 1
    if awk '{print $1}' <<<"$snaps" | grep -Fxq "$app"; then
      [[ "$source" == none ]] || alternate=true
      [[ "$WORKSTATION_DISTRO" == ubuntu && ( "$app" == discord || "$app" == firefox ) ]] || return 1
      id="$(desktop_utility_snap_id "$app")" || return 1
      info="$(snap info --unicode=never "$app")" || return 1
      [[ "$(awk '$1 == "snap-id:" {print $2}' <<<"$info")" == "$id" ]] || return 1
      source=snap
      if [[ "$path" == "/snap/bin/$app" || "$path" == "/var/lib/snapd/snap/bin/$app" \
        || ( -L "$path" && "$(readlink "$path")" == "/snap/bin/$app" ) \
        || ( -z "$path" && -x "/snap/bin/$app" ) \
        || ( "$app" == firefox && "$path" == /usr/bin/firefox && "$version" == *snap* ) ]]; then launcher=owned; fi
      [[ "$(awk -v app="$app" '$1 == app {print $4}' <<<"$snaps")" == latest/stable ]] || return 1
    fi
  fi
  if command -v flatpak &>/dev/null; then
    flatpaks="$(flatpak list --app --columns=application)" || return 1
    case "$app" in steam) id=com.valvesoftware.Steam ;; discord) id=com.discordapp.Discord ;;
      firefox) id=org.mozilla.firefox ;; mullvad) id=net.mullvad.MullvadVPN ;; esac
    if grep -Fxq "$id" <<<"$flatpaks"; then alternate=true; fi
  fi
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    case "$app" in
      steam)
        if [[ "$source" == native && -z "$path" && -x /usr/games/steam ]]; then launcher=owned; fi
        if native_package_installed steam-launcher; then alternate=true; fi
        if [[ "$source" == none ]] && native_package_installed steam:i386; then alternate=true; fi
        if grep -RqiE 'repo\.steampowered\.com|steamrepo' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then alternate=true; fi ;;
      firefox|mullvad)
        sources="$(work_app_apt_source "$app")" || return 1
        [[ "$source" != apt || -n "$sources" ]] || return 1
        [[ "$app" != firefox || -z "$sources" || "$source" == apt ]] || alternate=true ;;
      discord)
        if [[ "$source" == self-deb ]]; then
          dpkg-query -L discord | grep -Fx /usr/share/discord/updater_bootstrap >/dev/null || return 1
          [[ -x /usr/share/discord/updater_bootstrap ]] || return 1
        fi
        if grep -RqiE 'discord' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then alternate=true; fi ;;
    esac
    # Known unmanaged vendor trees, even off PATH, must not gain a duplicate package.
    case "$app" in
      discord) for root in /opt/Discord "$USER_HOME_DIR/Discord" "$USER_HOME_DIR/.local/share/Discord"; do
        [[ ! -e "$root" && ! -L "$root" ]] || alternate=true
      done
      [[ "$source" != none || ! -e /usr/share/discord ]] || alternate=true ;;
      firefox) for root in /opt/firefox "$USER_HOME_DIR/firefox" "$USER_HOME_DIR/.local/firefox"; do
        [[ ! -e "$root" && ! -L "$root" ]] || alternate=true
      done ;;
    esac
  fi
  personal_app_selection "$WORKSTATION_DISTRO" "$app" "$source" "$launcher" "$alternate" "$version"
}

install_discord_bootstrap() (
  local stage holds
  holds="$(apt-mark showhold)" || return 1
  if grep -Fxq discord <<<"$holds"; then
    print_error_message 'Missing Discord bootstrap is policy-held; preserved'; return 1
  fi
  ensure_native_pkgs curl ca-certificates || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsS \
    "https://stable.dl2.discordapp.net/apps/linux/$DISCORD_BOOTSTRAP_VERSION/discord-$DISCORD_BOOTSTRAP_VERSION.deb" -o "$stage/discord.deb" || return 1
  printf '%s  %s\n' "$DISCORD_BOOTSTRAP_SHA256" "$stage/discord.deb" | sha256sum -c - || return 1
  [[ "$(dpkg-deb -f "$stage/discord.deb" Package)" == discord \
    && "$(dpkg-deb -f "$stage/discord.deb" Architecture)" == amd64 \
    && "$(dpkg-deb -f "$stage/discord.deb" Version)" == "$DISCORD_BOOTSTRAP_VERSION" ]] || return 1
  chmod 755 "$stage" || return 1
  chmod 644 "$stage/discord.deb" || return 1
  sudo apt-get install --yes --no-remove "$stage/discord.deb" || return 1
)

ensure_personal_app() {
  local app="$1" recipe package owner sources desktop foreign
  recipe="$(personal_app_installed_selection "$app")" || { print_error_message "$app source/launcher conflict; preserved"; return 1; }
  read -r package owner <<<"$recipe"
  case "$app" in steam) desktop=steam.desktop ;; discord) desktop=discord.desktop ;;
    firefox) desktop=firefox.desktop ;; mullvad) desktop=mullvad-vpn.desktop ;; esac
  if [[ -e "$USER_HOME_DIR/.local/share/applications/$desktop" || -L "$USER_HOME_DIR/.local/share/applications/$desktop" ]]; then
    print_error_message "$app user desktop override preserved; resolve launcher conflict"; return 1
  fi
  if [[ "$owner" == snap && ( -e "$USER_HOME_DIR/.local/share/applications/${app}_${app}.desktop" || -L "$USER_HOME_DIR/.local/share/applications/${app}_${app}.desktop" ) ]]; then return 1; fi
  if [[ "$app" == steam && "$WORKSTATION_DISTRO" == ubuntu ]] && ! type -P steam &>/dev/null; then
    core_cli_link_allowed /usr/games/steam "$USER_HOME_DIR/.local/bin/steam" || return 1
    [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
  fi
  case "$WORKSTATION_DISTRO:$owner" in
    arch:native)
      if [[ "$app" == steam ]]; then
        ensure_multilib_enabled || return 1
        # Refresh/upgrade together, never leave Arch in a partial-upgrade state.
        [[ "${MULTILIB_CHANGED:-false}" != true ]] || safe_system_upgrade --yes || return 1
      fi
      ensure_native_pkgs "$package" || return 1 ;;
    arch:aur) ensure_yay_installed && ensure_yay_pkgs "$package" || return 1 ;;
    ubuntu:native)
      [[ "$(dpkg --print-architecture)" == amd64 ]] || return 1
      foreign="$(dpkg --print-foreign-architectures)" || return 1
      if ! grep -Fxq i386 <<<"$foreign"; then sudo dpkg --add-architecture i386 || return 1; fi
      ensure_native_pkgs software-properties-common || return 1
      sudo add-apt-repository --yes --component multiverse || return 1
      sudo apt-get update --error-on=any || return 1
      check_steam_candidates || return 1
      ensure_native_pkgs steam-installer steam-libs-i386:i386 || return 1
      if ! type -P steam &>/dev/null; then
        [[ -x /usr/games/steam && ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
        link_core_cli_config /usr/games/steam "$USER_HOME_DIR/.local/bin/steam" || return 1
      fi ;;
    ubuntu:apt)
      sources="$(work_app_apt_source "$app")" || return 1
      # Firefox APT is retained only; no pins/source migration from Ubuntu's Snap.
      [[ "$app" != firefox || -n "$sources" ]] || return 1
      ensure_work_app_apt_source "$app" "$sources" || return 1
      sudo apt-get update --error-on=any || return 1
      work_app_apt_candidate "$app" "$(apt-cache policy "$package")" >/dev/null || return 1
      ensure_native_pkgs "$package" || return 1 ;;
    ubuntu:self-deb)
      if ! native_package_installed discord; then install_discord_bootstrap || return 1; fi ;;
    ubuntu:snap)
      # Reuse the asserted Snap installer and command-link checks.
      ensure_personal_snap "$app" || return 1 ;;
    *) return 1 ;;
  esac
  personal_app_installed_selection "$app" >/dev/null || return 1
  desktop="$(personal_app_desktop "$app")" || return 1
  print_info_message "$app desktop: $desktop; update owner: $owner (Steam/Discord runtime also update in-app); runtime unverified"
  if [[ "$app" == discord && "$owner" == self-deb ]]; then
    print_info_message 'Discord bootstrap retained; its Rust updater owns app releases on launch; updater policy/settings unchanged'
  fi
}

ensure_personal_snap() {
  local app="$1"
  if ! type -P "$app" &>/dev/null; then
    core_cli_link_allowed "/snap/bin/$app" "$USER_HOME_DIR/.local/bin/$app" || return 1
    [[ ":$PATH:" == *":/snap/bin:"* || ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
  fi
  if ! command -v snap &>/dev/null; then ensure_native_pkgs snapd || return 1; fi
  if ! snap list --unicode=never "$app" &>/dev/null; then
    [[ "$(snap info --unicode=never "$app" | awk '$1 == "snap-id:" {print $2}')" == "$(desktop_utility_snap_id "$app")" ]] || return 1
    sudo snap install "$app" --channel=latest/stable || return 1
  fi
  if ! type -P "$app" &>/dev/null; then
    [[ -x "/snap/bin/$app" && ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || return 1
    link_core_cli_config "/snap/bin/$app" "$USER_HOME_DIR/.local/bin/$app" || return 1
  fi
}

personal_app_desktop() {
  local app="$1" recipe package owner file list
  recipe="$(personal_app_installed_selection "$app")" || return 1
  read -r package owner <<<"$recipe"
  case "$app" in steam) file=steam.desktop ;; discord) file=discord.desktop ;;
    firefox) file=firefox.desktop ;; mullvad) file=mullvad-vpn.desktop ;; esac
  if [[ "$owner" == snap ]]; then
    file="${app}_${app}.desktop"
    [[ -r "/var/lib/snapd/desktop/applications/$file" ]] || return 1
  else
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then list="$(pacman -Qlq "$package")" || return 1
    else list="$(dpkg-query -L "$package")" || return 1; fi
    grep -Fxq "/usr/share/applications/$file" <<<"$list" || return 1
    [[ -r "/usr/share/applications/$file" ]] || return 1
  fi
  # An overriding user launcher is not ours to replace or set as the default.
  [[ ! -e "$USER_HOME_DIR/.local/share/applications/$file" && ! -L "$USER_HOME_DIR/.local/share/applications/$file" ]] || return 1
  printf '%s\n' "$file"
}

check_steam_candidates() {
  local package policy indexes
  indexes="$(apt-cache policy)" || return 1
  for package in steam-installer steam-libs-i386:i386 libc6:i386; do
    policy="$(apt-cache policy "$package")" || return 1
    python3 "$DF_SCRIPT_DIR/work_app_metadata.py" steam-candidate "$package" "$policy" "$indexes" >/dev/null || {
      print_error_message 'Steam needs official Ubuntu multiverse and i386 indexes; source restrictions/pins preserved'; return 1;
    }
  done
}

check_personal_app_owners() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package recipe owner sources key stage snaps='' path
  if command -v snap &>/dev/null; then snaps="$(snap list --unicode=never 2>/dev/null)" || return 1; fi
  for app in steam discord firefox mullvad; do
    recipe="$(personal_app_selection ubuntu "$app" none '' false '')" || return 1
    read -r package _ <<<"$recipe"
    path="$(type -P "$app" || true)"
    if native_package_installed "$package" || [[ -n "$path" ]] || awk '{print $1}' <<<"$snaps" | grep -Fxq "$app"; then
      recipe="$(personal_app_installed_selection "$app")" || return 1
      read -r _ owner <<<"$recipe"
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

check_personal_app_candidates() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package version policy
  if native_package_installed discord; then
    policy="$(apt-cache policy discord)" || return 1
    if grep -q ' Packages' <<<"$policy"; then
      print_error_message 'Discord has an alternate APT update owner; preserved'; return 1
    fi
  fi
  if native_package_installed steam-installer; then check_steam_candidates || return 1; fi
  for app in mullvad firefox; do
    [[ "$app" != mullvad ]] && package=firefox || package=mullvad-vpn
    native_package_installed "$package" || continue
    version="$(dpkg-query -W -f='${Version}' "$package")" || return 1
    [[ "$app" != firefox || "$version" != *snap* ]] || continue
    work_app_apt_candidate "$app" "$(apt-cache policy "$package")" >/dev/null || return 1
  done
}
