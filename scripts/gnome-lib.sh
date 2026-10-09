#!/usr/bin/env bash
# Fixed GNOME recipes; metadata must support the installed shell before activation.
gnome_extension_recipe() {
  local shell="${3:-}"
  if [[ "$2" == pop && "${shell%%.*}" == 51 ]]; then
    case "$1" in
      arch|ubuntu) echo 'pop-shell@system76.com pop-31f04c3 pinned'; return 0 ;;
    esac
  fi
  case "$1:$2" in
    arch:pop) echo 'pop-shell@system76.com gnome-shell-extension-pop-shell-git aur' ;;
    arch:overview) echo 'no-overview@fthx gnome-shell-extension-no-overview aur' ;;
    arch:tray) echo 'appindicatorsupport@rgcjonas.gmail.com gnome-shell-extension-appindicator native' ;;
    arch:panel) echo 'dash-to-panel@jderose9.github.com gnome-shell-extension-dash-to-panel native' ;;
    arch:clipboard) echo 'GPaste@gnome-shell-extensions.gnome.org gpaste native' ;;
    ubuntu:tray) echo 'ubuntu-appindicators@ubuntu.com gnome-shell-ubuntu-extensions native' ;;
    ubuntu:clipboard) echo 'GPaste@gnome-shell-extensions.gnome.org gnome-shell-extension-gpaste native' ;;
    ubuntu:pop) echo 'pop-shell@system76.com pop-7898b65 pinned' ;;
    ubuntu:overview) echo 'no-overview@fthx overview-9246cc6 pinned' ;;
    ubuntu:panel) echo 'dash-to-panel@jderose9.github.com panel-v74 pinned' ;;
    *) return 1 ;;
  esac
}

gnome_extension_path() {
  local uuid="$1" user="$USER_HOME_DIR/.local/share/gnome-shell/extensions/$1"
  if [[ -e "$user" || -L "$user" ]]; then printf '%s\n' "$user";
  else printf '/usr/share/gnome-shell/extensions/%s\n' "$uuid"; fi
}

gnome_extension_link_allowed() {
  local target="$1" root="$USER_HOME_DIR/.local/share/dotfiles-arch/gnome" resolved pin
  core_cli_parent_links_allowed "$target" || return 1
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -L "$target" ]] || return 1
  resolved="$(readlink "$target")" || return 1
  [[ "$resolved" == "$root/"* && "$resolved" != *'..'* ]] || return 1
  pin="${resolved#"$root"/}"; pin="${pin%%/*}"
  [[ -d "$root/$pin" && ! -L "$root/$pin" && -O "$root/$pin" \
    && -f "$root/$pin/.dfa-gnome" && ! -L "$root/$pin/.dfa-gnome" \
    && "$(cat "$root/$pin/.dfa-gnome")" == 'dotfiles-arch GNOME' ]]
}

install_gnome_extension_pin() (
  local uuid="$1" id="$2" version="$3" url sha kind root dest stage source
  case "$id" in
    pop-31f04c3)
      url=https://codeload.github.com/pop-os/shell/tar.gz/31f04c32d2fbf92afcd3dd5194ac16755008bae2
      sha=e25e0f2e1f558a2a63cd6b1a948e6c429f3512a199681ed0509613e77b132f82; kind=tar ;;
    pop-7898b65)
      url=https://codeload.github.com/pop-os/shell/tar.gz/7898b65c20735057faf0797f8ed056704ca55f0d
      sha=f1c4679dadf0d32054a180d65b3b543a3877c43e23f509328598322c3e143296; kind=tar ;;
    overview-9246cc6)
      url=https://codeload.github.com/fthx/no-overview/tar.gz/9246cc6efba01729a3e19ca898018ab5e98a26b9
      sha=126117235b7644c049f3a8d8fd371053c620fab04258dede3d64cf2dbe5b043e; kind=tar ;;
    panel-v74)
      url='https://github.com/home-sweet-gnome/dash-to-panel/releases/download/v74/dash-to-panel%40jderose9.github.com_v74.zip'
      sha=a4344e3143b37aafd1dff71d2daec30a953f55a44fd606e3fe10d46ee1c1582a; kind=zip ;;
    *) return 1 ;;
  esac
  root="$USER_HOME_DIR/.local/share/dotfiles-arch/gnome"
  dest="$root/$id-$sha"
  core_cli_parent_links_allowed "$dest" || return 1
  if [[ -e "$dest" || -L "$dest" ]]; then
    [[ -d "$dest" && ! -L "$dest" && -O "$dest" && -f "$dest/.dfa-gnome" && ! -L "$dest/.dfa-gnome" \
      && "$(cat "$dest/.dfa-gnome")" == 'dotfiles-arch GNOME' ]] || return 1
  else
    stage="$(mktemp -d)" || return 1
    trap 'rm -rf "$stage"' EXIT
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$stage/archive" || return 1
    [[ "$(sha256sum "$stage/archive" | awk '{print $1}')" == "$sha" ]] || {
      print_error_message "GNOME extension checksum mismatch: $uuid; preserved" >&2; return 1;
    }
    source="$stage/source"
    python3 "$DF_SCRIPT_DIR/gnome_desktop.py" stage "$kind" "$stage/archive" "$source" || return 1
    python3 "$DF_SCRIPT_DIR/gnome_desktop.py" compatible "$source/metadata.json" "$uuid" "$version" || return 1
    if [[ "$id" == pop-* ]]; then
      # Compile verified TypeScript only. Never run upstream local-install/configure,
      # which resets user shortcuts and may restart the session.
      (cd "$source" && /usr/bin/tsc --project src/color_dialog \
        && /usr/bin/tsc --project src/floating_exceptions && /usr/bin/tsc) || return 1
      mkdir "$stage/content" || return 1
      cp -R "$source/target/." "$stage/content/" || return 1
      cp -R "$source/metadata.json" "$source/icons" "$source/schemas" "$source/"*.css "$stage/content/" || return 1
    else
      mv "$source" "$stage/content" || return 1
    fi
    if [[ -d "$stage/content/schemas" ]]; then
      glib-compile-schemas --strict "$stage/content/schemas" || return 1
    fi
    [[ -f "$stage/content/extension.js" ]] || return 1
    printf '%s\n' 'dotfiles-arch GNOME' >"$stage/content/.dfa-gnome" || return 1
    mkdir -p "$root" || return 1
    mv -T "$stage/content" "$dest" || return 1
  fi
  python3 "$DF_SCRIPT_DIR/gnome_desktop.py" compatible "$dest/metadata.json" "$uuid" "$version" || return 1
  mkdir -p "$USER_HOME_DIR/.local/share/gnome-shell/extensions" || return 1
  ln -sfnT "$dest" "$USER_HOME_DIR/.local/share/gnome-shell/extensions/$uuid"
)

ensure_gnome_extensions() {
  local version="$1" app recipe uuid package owner target path daemon_package client skips installed=false
  local -a required=() apps=(pop overview tray panel clipboard)
  skips="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" skips "$version")" || return 1
  # Consumed by setup-gnome.sh; skip only the explicitly accepted newer-shell gap.
  # shellcheck disable=SC2034
  GNOME_POP_SHELL_AVAILABLE=true
  if [[ "$skips" == pop-shell@system76.com ]]; then
    GNOME_POP_SHELL_AVAILABLE=false
    apps=(overview tray panel clipboard)
    print_warning_message "Accepted feature gap: Pop Shell skipped on GNOME $version (supported through GNOME 51); native window moves remain available"
  fi
  # Repair the legacy bypass even when a required extension needs a source update.
  gsettings set org.gnome.shell disable-extension-version-validation false || return 1
  daemon_package=gpaste
  [[ "$WORKSTATION_DISTRO" != ubuntu ]] || daemon_package=gpaste-2
  native_package_installed "$daemon_package" && installed=true
  client="$(type -P gpaste-client || true)"
  [[ -z "$client" ]] || client="$(readlink -f "$client")"
  if ! core_cli_source_allowed "$installed" "$client" /usr/bin/gpaste-client \
    || { [[ "$installed" == false ]] && [[ -e /usr/bin/gpaste-client || -L /usr/bin/gpaste-client ]]; }; then
    print_error_message 'GPaste client source conflict; existing client preserved'
    return 1
  fi
  # Preflight every source conflict before adding packages or replacing links.
  for app in "${apps[@]}"; do
    recipe="$(gnome_extension_recipe "$WORKSTATION_DISTRO" "$app" "$version")" || return 1
    read -r uuid package owner <<<"$recipe"
    if [[ -e "/usr/local/share/gnome-shell/extensions/$uuid" || -L "/usr/local/share/gnome-shell/extensions/$uuid" ]]; then
      print_error_message "Unowned system-local extension: $uuid; preserved"
      return 1
    fi
    target="$USER_HOME_DIR/.local/share/gnome-shell/extensions/$uuid"
    if [[ "$owner" == pinned ]]; then
      # The GNOME 51 pin supersedes only the known Arch AUR copy. Keep its
      # package/files intact; unowned or other system copies remain conflicts.
      local system_allowed=false
      if [[ "$WORKSTATION_DISTRO:$app:$package" == arch:pop:pop-31f04c3 ]] \
        && [[ "$(pacman -Qoq "/usr/share/gnome-shell/extensions/$uuid/metadata.json" 2>/dev/null)" == gnome-shell-extension-pop-shell-git ]]; then
        system_allowed=true
      fi
      if ! gnome_extension_link_allowed "$target" || { [[ "$system_allowed" == false ]] \
        && [[ -e "/usr/share/gnome-shell/extensions/$uuid" || -L "/usr/share/gnome-shell/extensions/$uuid" ]]; }; then
        print_error_message "GNOME source conflict: $uuid; existing extension preserved. Explicitly migrate its owner before setup."
        return 1
      fi
    elif [[ -e "$target" || -L "$target" ]]; then
      print_error_message "User extension shadows selected $package: $target; preserved"
      return 1
    fi
  done
  for app in "${apps[@]}"; do
    recipe="$(gnome_extension_recipe "$WORKSTATION_DISTRO" "$app" "$version")" || return 1
    read -r uuid package owner <<<"$recipe"
    case "$owner" in
      native) ensure_native_pkgs "$package" || return $? ;;
      aur) ensure_yay_pkgs "$package" || return $? ;;
      pinned)
        if [[ "$WORKSTATION_DISTRO" == arch ]]; then
          ensure_native_pkgs curl ca-certificates python glib2 || return $?
          if [[ "$app" == pop ]]; then ensure_native_pkgs typescript || return $?; fi
        else
          ensure_native_pkgs curl ca-certificates python3 libglib2.0-bin || return $?
          if [[ "$app" == pop ]]; then ensure_native_pkgs node-typescript || return $?; fi
        fi
        install_gnome_extension_pin "$uuid" "$package" "$version" || return 1 ;;
      *) return 1 ;;
    esac
    path="$(gnome_extension_path "$uuid")" || return 1
    if [[ "$owner" != pinned ]]; then
      case "$WORKSTATION_DISTRO" in
        arch) [[ "$(pacman -Qoq "$path/metadata.json" 2>/dev/null)" == "$package" ]] ;;
        ubuntu) dpkg-query -S "$path/metadata.json" 2>/dev/null | grep -Fxq "$package: $path/metadata.json" ;;
      esac || { print_error_message "GNOME package ownership conflict: $uuid; preserved"; return 1; }
    fi
    print_info_message "GNOME extension: $uuid; update owner=$owner ($package)"
    python3 "$DF_SCRIPT_DIR/gnome_desktop.py" compatible "$path/metadata.json" "$uuid" "$version" || return 1
    required+=("$uuid")
  done
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    ensure_native_pkgs gpaste-2 gir1.2-gpaste-2 || return $?
  fi
  [[ "$(readlink -f "$(type -P gpaste-client)")" == /usr/bin/gpaste-client ]] || {
    print_error_message 'GPaste launcher source conflict; selected native client is shadowed'; return 1;
  }
  local lists enabled disabled
  enabled="$(gsettings get org.gnome.shell enabled-extensions)" || return 1
  disabled="$(gsettings get org.gnome.shell disabled-extensions)" || return 1
  lists="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" lists "$WORKSTATION_DISTRO" "$version" "$enabled" "$disabled" "${required[@]}")" || return 1
  if [[ "$GNOME_POP_SHELL_AVAILABLE" == false ]]; then
    gnome-extensions disable pop-shell@system76.com 2>/dev/null || true
  fi
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    local conflict
    for conflict in ubuntu-dock@ubuntu.com tiling-assistant@ubuntu.com ding@rastersoft.com appindicatorsupport@rgcjonas.gmail.com; do
      gnome-extensions disable "$conflict" 2>/dev/null || true
    done
  fi
  gsettings set org.gnome.shell disabled-extensions "${lists#*$'\n'}" || return 1
  gsettings set org.gnome.shell enabled-extensions "${lists%%$'\n'*}" || return 1
  gsettings set org.gnome.shell disable-user-extensions false || return 1
}

# User extension schemas are local, not installed into the global GLib registry.
gnome_extension_setting() {
  local uuid="$1" schema="$2" key="$3" value="$4" optional="${5:-false}" path
  local -a settings=(gsettings)
  path="$(gnome_extension_path "$uuid")" || return 1
  [[ ! -f "$path/schemas/gschemas.compiled" ]] || settings+=(--schemadir "$path/schemas")
  if ! "${settings[@]}" list-keys "$schema" 2>/dev/null | grep -Fx "$key" >/dev/null; then
    if [[ "$optional" == true ]]; then
      print_warning_message "Optional GNOME setting unavailable: $schema $key"; return 0
    fi
    print_error_message "Required GNOME setting unavailable: $schema $key; update its selected source"
    return 1
  fi
  "${settings[@]}" set "$schema" "$key" "$value"
}

# Preserve unknown local/managed policies and symlinks. Package defaults in /usr/lib
# remain distro-owned; explicit overrides in /etc or /run take precedence over ours.
gnome_write_policy() {
  local target="$1" kind="$2" pattern="$3" content="$4" existing='' conflict=false file action stage
  shift 4
  if ! core_cli_parent_links_allowed "$target" || [[ -L "$target" || ( -e "$target" && ! -f "$target" ) ]]; then conflict=true;
  elif [[ -f "$target" ]]; then existing="$(cat "$target")" || return 1; fi
  for file in "$@"; do
    [[ -e "$file" && "$file" != "$target" ]] || continue
    if grep -Eq "$pattern" "$file"; then conflict=true; fi
  done
  action="$(python3 "$DF_SCRIPT_DIR/gnome_desktop.py" policy "$existing" "$conflict" "$kind")" || return 1
  if [[ "$action" == defer ]]; then
    # Consumed by setup-gnome.sh after this sourced helper returns.
    # shellcheck disable=SC2034
    GNOME_POLICIES_DEFERRED=true
    print_warning_message "Preserved external $kind policy; skipped $target"
    return 0
  fi
  stage="$(mktemp)" || return 1
  printf '%s\n' "$content" >"$stage" || { rm -f "$stage"; return 1; }
  if ! sudo install -D -m 0644 "$stage" "$target"; then rm -f "$stage"; return 1; fi
  rm -f "$stage"
}

gnome_service_loaded() {
  local scope="$1" unit="$2" state
  if [[ "$scope" == user ]]; then state="$(systemctl --user show "$unit" -p LoadState --value)" || return 1;
  else state="$(systemctl show "$unit" -p LoadState --value)" || return 1; fi
  [[ "$state" == loaded ]]
}
