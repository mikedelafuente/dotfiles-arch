#!/usr/bin/env bash
# Read-only decisions use supplied source/version facts, never package operations.
desktop_ide_zed_version() {
  local pattern='^Zed ([0-9]+\.[0-9]+\.[0-9]+)($|[[:space:]])'
  [[ "$1" =~ $pattern ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

desktop_ide_selection() {
  local distro="$1" app="$2" source="$3" version="$4"
  case "$distro" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$app" in
    zed)
      if [[ "$source" != none ]]; then
        core_cli_version_at_least "$version" 1.18.0 || {
          print_error_message 'Zed 1.18+ required for shared terminal-thread settings; installation preserved' >&2; return 1;
        }
      fi
      case "$source:$distro" in
        native:*) echo native ;;
        user:*) echo self ;;
        none:arch) echo native ;;
        none:ubuntu) echo self ;;
        *) print_error_message 'Zed source conflict; preserved' >&2; return 1 ;;
      esac ;;
    orca)
      case "$source:$distro" in
        native:arch|none:arch) echo aur ;;
        native:ubuntu) echo release-deb ;;
        appimage:*|none:ubuntu) echo self ;;
        *) print_error_message 'Orca source conflict; preserved' >&2; return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
}

# Never claim folders/browser/PIM types or replace an unrelated default.
desktop_ide_mime_allowed() {
  case "$1" in inode/directory|text/html|text/calendar|text/vcard|text/x-vcard) return 1 ;; esac
  [[ -z "$2" || "$2" == "$3" ]]
}

# Pin exact official stable amd64 asset names and require GitHub's SHA-256 digest.
desktop_ide_release_asset() {
  local app="$1" metadata="$2" repo asset tag version fields url digest
  tag="$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$metadata")" || return 1
  [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || return 1
  version="${BASH_REMATCH[1]}"
  case "$app" in
    zed) repo=zed-industries/zed; asset=zed-linux-x86_64.tar.gz
      core_cli_version_at_least "$version" 1.18.0 || return 1 ;;
    orca) repo=stablyai/orca; asset=orca-linux.AppImage ;;
    orca-deb) repo=stablyai/orca; asset="orca-ide_${version}_amd64.deb" ;;
    *) return 1 ;;
  esac
  fields="$(jq -er --arg name "$asset" '[.assets[] | select(.name == $name)] | select(length == 1) | .[0] | [.browser_download_url, .digest] | @tsv' <<<"$metadata")" || return 1
  read -r url digest <<<"$fields"
  [[ "$url" == "https://github.com/$repo/releases/download/$tag/$asset" && "$digest" =~ ^sha256:([a-f0-9]{64})$ ]] || return 1
  printf '%s %s %s\n' "$version" "$url" "${BASH_REMATCH[1]}"
}

# Gather the selected command, rejecting differently resolved aliases.
desktop_ide_command() {
  local app="$1" name found='' resolved candidate
  local -a names
  case "$app" in zed) names=(zeditor zed) ;; orca) names=(stably-orca orca-ide) ;; *) return 1 ;; esac
  for name in "${names[@]}"; do
    candidate="$(type -P "$name" || true)"
    [[ -n "$candidate" ]] || continue
    resolved="$(readlink -f "$candidate")" || return 1
    [[ -z "$found" || "$found" == "$resolved" ]] || {
      print_error_message "$app launcher conflict; preserved" >&2; return 1;
    }
    found="$resolved"
  done
  printf '%s\n' "$found"
}

# User Zed is recognized only at its official stable layout. Unknown sources fail.
desktop_ide_source() {
  local app="$1" binary="$2" package
  case "$app:$WORKSTATION_DISTRO" in
    zed:arch) package=zed ;;
    zed:ubuntu) package=zed-editor
      native_package_installed zed && package=zed ;;
    orca:arch) package=stably-orca-bin ;;
    orca:ubuntu) package=orca-ide ;;
    *) return 1 ;;
  esac
  if native_package_installed "$package"; then
    [[ -n "$binary" ]] || { echo unknown; return; }
    case "$WORKSTATION_DISTRO" in
      arch) pacman -Qo "$binary" 2>/dev/null | grep -Fq " is owned by $package " ;;
      ubuntu) dpkg-query -S "$binary" 2>/dev/null | grep -Fxq "$package: $binary" ;;
    esac || { echo conflict; return; }
    echo native
  elif [[ -z "$binary" ]]; then
    echo none
  elif [[ "$app" == zed && "$binary" == "$USER_HOME_DIR/.local/zed.app/bin/zed" && -x "$USER_HOME_DIR/.local/zed.app/libexec/zed-editor" ]]; then
    echo user
  elif [[ "$app" == orca && "$binary" == *.AppImage && "$(od -An -tx1 -j8 -N3 "$binary" | tr -d ' \n')" == 414902 ]]; then
    echo appimage
  else
    echo unknown
  fi
}

# No installer scripts. Verify the official artifact before exposing any command.
install_desktop_ide_release() (
  local app="$1" repo metadata release version url digest stage root
  case "$app" in zed) repo=zed-industries/zed ;; orca|orca-deb) repo=stablyai/orca ;; *) return 1 ;; esac
  metadata="$(curl --proto '=https' --tlsv1.2 -fsSL "https://api.github.com/repos/$repo/releases/latest")" || return 1
  release="$(desktop_ide_release_asset "$app" "$metadata")" || {
    print_error_message "Unresolved $app stable amd64 artifact compatibility/integrity; preserved"; return 1;
  }
  read -r version url digest <<<"$release"
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$stage/artifact" || return 1
  printf '%s  %s\n' "$digest" "$stage/artifact" | sha256sum -c - || return 1
  case "$app" in
    zed)
      root="$USER_HOME_DIR/.local/zed.app"
      [[ ! -e "$root" && ! -L "$root" ]] || return 1
      python3 - "$stage/artifact" "$stage" <<'PY' || return 1
import sys, tarfile
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    members = archive.getmembers()
    if any(m.name.split('/')[0] != 'zed.app' for m in members):
        raise ValueError('Unexpected Zed archive layout')
    archive.extractall(sys.argv[2], members=members, filter='data')
PY
      [[ -x "$stage/zed.app/bin/zed" && -x "$stage/zed.app/libexec/zed-editor" ]] || return 1
      local actual
      actual="$("$stage/zed.app/bin/zed" --version)" || return 1
      actual="$(desktop_ide_zed_version "$actual")" || return 1
      [[ "$actual" == "$version" ]] || return 1
      mkdir -p "$USER_HOME_DIR/.local" || return 1
      mv -T "$stage/zed.app" "$root" || return 1
      link_core_cli_config "$root/bin/zed" "$USER_HOME_DIR/.local/bin/zed" || return 1 ;;
    orca)
      root="$USER_HOME_DIR/.local/share/dotfiles-arch/orca"
      [[ ! -e "$root" && ! -L "$root" ]] || return 1
      [[ "$(od -An -tx1 -j8 -N3 "$stage/artifact" | tr -d ' \n')" == 414902 ]] || return 1
      # Ubuntu's t64 FUSE2 supplies AppImage mounting without disabling sandboxing.
      ensure_native_pkgs libfuse2t64 || return 1
      mkdir -p "$root" || return 1
      install -m755 "$stage/artifact" "$root/Orca.AppImage" || return 1
      link_core_cli_config "$root/Orca.AppImage" "$USER_HOME_DIR/.local/bin/orca-ide" || return 1 ;;
    orca-deb)
      [[ "$(dpkg-deb -f "$stage/artifact" Package)" == orca-ide \
        && "$(dpkg-deb -f "$stage/artifact" Architecture)" == amd64 \
        && "$(dpkg-deb -f "$stage/artifact" Version)" == "$version" ]] || return 1
      if native_package_installed orca-ide; then
        local installed
        installed="$(dpkg-query -W -f='${Version}' orca-ide)" || return 1
        dpkg --compare-versions "$installed" lt "$version" || return 0
        local holds
        holds="$(apt-mark showhold)" || return 1
        if grep -Fxq orca-ide <<<"$holds"; then
          print_error_message 'orca-ide is held; preserved'; return 1
        fi
      fi
      chmod 755 "$stage" || return 1
      mv "$stage/artifact" "$stage/orca.deb" || return 1
      chmod 644 "$stage/orca.deb" || return 1
      sudo apt-get install --no-remove -y "$stage/orca.deb" || return 1 ;;
  esac
)

# Existing DEBs notify only: the common updater explicitly refreshes this owner.
refresh_desktop_ides() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  native_package_installed orca-ide || return 0
  local binary source
  binary="$(desktop_ide_command orca)" || return 1
  source="$(desktop_ide_source orca "$binary")" || return 1
  [[ "$source" == native ]] || { print_error_message 'Orca update source conflict; preserved'; return 1; }
  install_desktop_ide_release orca-deb
}

# Setup preflights aliases/config/desktop destinations before acquisition.
ensure_desktop_ide() {
  local app="$1" binary source version='' owner canonical alias desktop target root
  binary="$(desktop_ide_command "$app")" || return 1
  source="$(desktop_ide_source "$app" "$binary")" || return 1
  if [[ "$app" == zed && ( "$source" == native || "$source" == user ) ]]; then
    version="$("$binary" --version)" || return 1
    version="$(desktop_ide_zed_version "$version")" || return 1
  fi
  owner="$(desktop_ide_selection "$WORKSTATION_DISTRO" "$app" "$source" "$version")" || return 1
  case "$app" in
    zed)
      canonical=zed; alias=zeditor; desktop=dev.zed.Zed.desktop
      root="$USER_HOME_DIR/.local/zed.app"
      [[ -n "$binary" ]] || {
        if [[ "$owner" == self ]]; then binary="$root/bin/zed"; else binary=/usr/bin/zeditor; fi
      }
      editor_config_allowed "$DF_SCRIPT_DIR/../config/zed" "$USER_HOME_DIR/.config/zed" || {
        print_error_message 'Zed config conflict; preserved'; return 1;
      } ;;
    orca)
      canonical=orca-ide; alias=stably-orca; desktop=dfa-orca.desktop
      root="$USER_HOME_DIR/.local/share/dotfiles-arch/orca"
      [[ -n "$binary" ]] || {
        if [[ "$owner" == self ]]; then binary="$root/Orca.AppImage"; else binary=/usr/bin/stably-orca; fi
      } ;;
    *) return 1 ;;
  esac
  for target in "$canonical" "$alias"; do
    # Real vendor commands already on PATH are retained; missing aliases use links.
    if ! type -P "$target" &>/dev/null; then
      core_cli_link_allowed "$binary" "$USER_HOME_DIR/.local/bin/$target" || {
        print_error_message "$target command conflict; preserved"; return 1;
      }
    fi
  done
  target="$USER_HOME_DIR/.local/share/applications/$desktop"
  local parent
  parent="$(dirname "$target")"
  while [[ "$parent" != / ]]; do
    [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || {
      print_error_message "Desktop directory conflict: $parent; preserved"; return 1;
    }
    parent="$(dirname "$parent")"
  done
  [[ ! -L "$target" ]] || { print_error_message "Desktop link conflict: $target; preserved"; return 1; }
  if [[ -e "$target" || -L "$target" ]]; then
    # Do not rewrite any existing desktop entry. Require its launcher to match.
    grep -Fq "$binary" "$target" || {
      print_error_message "Desktop entry conflict: $target; preserved"; return 1;
    }
  fi
  if [[ "$owner" == release-deb ]]; then
    ensure_native_pkgs curl jq ca-certificates || return 1
  fi
  if [[ "$source" == none ]]; then
    [[ ":$PATH:" == *":$USER_HOME_DIR/.local/bin:"* ]] || {
      print_error_message 'Add USER_HOME_DIR/.local/bin to PATH before IDE setup'; return 1;
    }
    # Report stale/off-PATH user installations instead of duplicating a source.
    if [[ "$owner" == self && ( -e "$root" || -L "$root" ) ]]; then
      print_error_message "$app existing user tree has no selected launcher; preserved"; return 1
    fi
    case "$owner" in
      native) ensure_native_pkgs zed || return 1 ;;
      aur) ensure_yay_installed && ensure_yay_pkgs stably-orca-bin || return 1 ;;
      self) ensure_native_pkgs curl jq ca-certificates || return 1
        if [[ "$app" == zed ]]; then ensure_native_pkgs python3 || return 1; fi
        install_desktop_ide_release "$app" || return 1 ;;
      *) return 1 ;;
    esac
  fi
  [[ -x "$binary" ]] || { print_error_message "$app launcher missing after acquisition"; return 1; }
  for target in "$canonical" "$alias"; do
    type -P "$target" &>/dev/null || link_core_cli_config "$binary" "$USER_HOME_DIR/.local/bin/$target" || return 1
  done
  # Package desktop entries remain vendor-owned. Self-updating apps get a separate
  # minimal user entry only when absent; no directory association is declared.
  if [[ "$owner" == self && ! -e "$USER_HOME_DIR/.local/share/applications/$desktop" ]]; then
    mkdir -p "$USER_HOME_DIR/.local/share/applications" || return 1
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec="%s" %%F\nTerminal=false\nCategories=Development;IDE;\n' \
      "$app" "$binary" >"$USER_HOME_DIR/.local/share/applications/$desktop" || return 1
  fi
  if [[ "$app" == zed ]]; then
    link_editor_config "$DF_SCRIPT_DIR/../config/zed" "$USER_HOME_DIR/.config/zed" || return 1
    if ! compgen -G '/usr/share/vulkan/icd.d/*.json' >/dev/null; then
      print_warning_message 'Zed requires Vulkan; no ICD found. Runtime support is unverified; drivers were not changed.'
    else
      print_info_message 'Vulkan ICD present; GPU/Wayland and shared Zed settings runtime remain unverified.'
    fi
  fi
  print_info_message "$app update owner: $owner (self requires in-app updates enabled)"
  print_info_message "$app installation, desktop launch and update runtime remain unverified"
}
