#!/usr/bin/env bash
# Fixed appearance recipes. Pin changes are reviewed by the maintainer, applied by setup/sync.
appearance_font_packages() {
  case "$1" in
    arch) echo 'adwaita-fonts noto-fonts noto-fonts-emoji ttf-liberation fontconfig ttf-meslo-nerd ttf-ubuntu-nerd ttf-firacode-nerd ttf-jetbrains-mono-nerd ttf-hack-nerd' ;;
    ubuntu) echo 'fonts-adwaita-sans fonts-noto-core fonts-noto-mono fonts-noto-color-emoji fonts-liberation fontconfig' ;;
    *) return 1 ;;
  esac
}

appearance_missing_families() {
  local supplied="$1" family missing=false
  for family in 'Adwaita Sans' 'Adwaita Mono' 'Noto Sans' 'Noto Serif' 'Noto Sans Mono' \
    'Noto Color Emoji' 'Liberation Sans' 'Liberation Serif' 'Liberation Mono' \
    'JetBrainsMono Nerd Font' 'MesloLGS Nerd Font' 'Ubuntu Nerd Font' 'FiraCode Nerd Font' 'Hack Nerd Font'; do
    if ! tr ',' '\n' <<<"$supplied" | grep -Fxq "$family"; then
      printf '%s\n' "$family"
      missing=true
    fi
  done
  [[ "$missing" == false ]]
}

# Only links into marked recipe directories are replaceable. Real/unrelated assets stay intact.
appearance_link_allowed() {
  local root="$1" target="$2" resolved relative pin
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -L "$target" ]] || return 1
  resolved="$(readlink "$target")" || return 1
  [[ "$resolved" == "$root/"* ]] || return 1
  relative="${resolved#"$root"/}"
  [[ "$relative" != *'..'* ]] || return 1
  pin="${relative%%/*}"
  [[ -f "$root/$pin/.dfa-appearance" && ! -L "$root/$pin/.dfa-appearance" ]] \
    && [[ "$(cat "$root/$pin/.dfa-appearance")" == 'dotfiles-arch appearance' ]]
}

appearance_root() { printf '%s/.local/share/dotfiles-arch/appearance\n' "$USER_HOME_DIR"; }

# Stage verified data only, never execute a downloaded installer.
install_appearance_asset() (
  local id="$1" url="$2" sha="$3" kind="$4" root dest stage
  [[ "$EUID" != 0 && -z "${SUDO_USER:-}" ]] || {
    print_error_message 'Run appearance setup as the workstation user, without sudo' >&2; return 1;
  }
  root="$(appearance_root)"
  dest="$root/$id-$sha"
  core_cli_parent_links_allowed "$dest" || return 1
  if [[ -e "$dest" || -L "$dest" ]]; then
    [[ -d "$dest" && ! -L "$dest" && -O "$dest" && -f "$dest/.dfa-appearance" \
      && "$(cat "$dest/.dfa-appearance")" == 'dotfiles-arch appearance' ]] || {
      print_error_message "Appearance source conflict: $dest; preserved"; return 1;
    }
    printf '%s\n' "$dest"
    return 0
  fi
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$stage/artifact" || return 1
  [[ "$(sha256sum "$stage/artifact" | awk '{print $1}')" == "$sha" ]] || {
    print_error_message "Appearance checksum mismatch: $id; existing assets preserved" >&2; return 1;
  }
  python3 "$DF_SCRIPT_DIR/appearance-assets.py" "$kind" "$stage/artifact" "$stage/content" || return 1
  printf '%s\n' 'dotfiles-arch appearance' >"$stage/content/.dfa-appearance" || return 1
  mkdir -p "$root" || return 1
  mv -T "$stage/content" "$dest" || return 1
  printf '%s\n' "$dest"
)

link_appearance_asset() {
  local source="$1" target="$2" root
  root="$(appearance_root)"
  if ! core_cli_parent_links_allowed "$target" || ! appearance_link_allowed "$root" "$target"; then
    print_error_message "Appearance target conflict: $target; preserved"; return 1
  fi
  [[ -e "$source" ]] || { print_error_message "Missing appearance asset: $source"; return 1; }
  mkdir -p "$(dirname "$target")" || return 1
  ln -sfnT "$source" "$target" || return 1
}

ensure_ubuntu_fonts() {
  local font sha dest root families family target
  root="$(appearance_root)"
  families="$(fc-list --format '%{family}\n')" || return 1
  for font in AdwaitaMono JetBrainsMono Meslo Ubuntu FiraCode Hack; do
    if ! core_cli_parent_links_allowed "$USER_HOME_DIR/.local/share/fonts/dfa-$font" \
      || ! appearance_link_allowed "$root" "$USER_HOME_DIR/.local/share/fonts/dfa-$font"; then
      print_error_message "Font source conflict: $font; preserved"; return 1
    fi
    target="$USER_HOME_DIR/.local/share/fonts/dfa-$font"
    case "$font" in
      AdwaitaMono) family='Adwaita Mono' ;;
      JetBrainsMono) family='JetBrainsMono Nerd Font' ;;
      Meslo) family='MesloLGS Nerd Font' ;;
      Ubuntu) family='Ubuntu Nerd Font' ;;
      FiraCode) family='FiraCode Nerd Font' ;;
      Hack) family='Hack Nerd Font' ;;
    esac
    if [[ ! -L "$target" ]] && tr ',' '\n' <<<"$families" | grep -Fxq "$family"; then
      print_error_message "Existing $family has another source; preserve its owner or explicitly migrate before font setup"
      return 1
    fi
  done
  ensure_native_pkgs curl ca-certificates python3 xz-utils || return $?
  dest="$(install_appearance_asset AdwaitaMono-49.0 https://download.gnome.org/sources/adwaita-fonts/49/adwaita-fonts-49.0.tar.xz \
    3157c620eb5b72b25ab156d194aa4eb223f9870d547fe83fdbdf06d3e7becb37 adwaita)" || return 1
  link_appearance_asset "$dest" "$USER_HOME_DIR/.local/share/fonts/dfa-AdwaitaMono" || return 1
  for font in JetBrainsMono Meslo Ubuntu FiraCode Hack; do
    case "$font" in
      JetBrainsMono) sha=04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf ;;
      Meslo) sha=6b6624632dc6873dfb7681c3f818e7c01ab601ab707690b6440933bbe57e2b11 ;;
      Ubuntu) sha=e84b2dbb9e6303e6ce45f0c80e6a083b31fda329fd0de0dd21fb8f851be141bd ;;
      FiraCode) sha=68e3bd6164864b8b514605bc34e3a87ac401c8c48682fcce6478c70263340207 ;;
      Hack) sha=cdd389472e10e2261520140ff1b382b4f8a226af5fd0b2735b975d31151d9c3c ;;
    esac
    dest="$(install_appearance_asset "$font-3.5.1" "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/$font.tar.xz" "$sha" fonts)" || return 1
    link_appearance_asset "$dest" "$USER_HOME_DIR/.local/share/fonts/dfa-$font" || return 1
  done
}

ensure_bat_appearance() {
  local binary dest target="$USER_HOME_DIR/.config/bat/themes/Catppuccin Mocha.tmTheme"
  binary="$(command -v bat || command -v batcat)" || return 1
  # Refresh our pinned theme even when its previous version is already cached.
  # Otherwise prefer the native built-in theme and retain compatible user themes.
  "$binary" cache --build >/dev/null || return 1
  if [[ ! -L "$target" ]] || ! appearance_link_allowed "$(appearance_root)" "$target"; then
    if "$binary" --list-themes | grep -Fxq 'Catppuccin Mocha'; then return 0; fi
  fi
  if ! core_cli_parent_links_allowed "$target" || ! appearance_link_allowed "$(appearance_root)" "$target"; then
    print_error_message "bat theme source conflict; preserved"; return 1
  fi
  ensure_native_pkgs curl ca-certificates || return $?
  if [[ "$WORKSTATION_DISTRO" == arch ]]; then
    ensure_native_pkgs python || return $?
  else
    ensure_native_pkgs python3 || return $?
  fi
  dest="$(install_appearance_asset bat-6810349 'https://raw.githubusercontent.com/catppuccin/bat/6810349b28055dce54076712fc05fc68da4b8ec0/themes/Catppuccin%20Mocha.tmTheme' \
    395566f08ceb301b936b91c077690ef94f7aeb651b121553f201c99c2bd4aa77 bat)" || return 1
  link_appearance_asset "$dest/Catppuccin Mocha.tmTheme" "$target" || return 1
  "$binary" cache --build >/dev/null && "$binary" --list-themes | grep -Fxq 'Catppuccin Mocha'
}

ensure_gnome_appearance() {
  local theme=catppuccin-mocha-lavender-standard+default dest target root version overlay stage
  root="$(appearance_root)"
  if [[ "$WORKSTATION_DISTRO" == arch ]]; then
    ensure_native_pkgs papirus-icon-theme || return $?
    ensure_yay_pkgs catppuccin-gtk-theme-mocha papirus-folders-catppuccin-git || return $?
    [[ -f "/usr/share/themes/$theme/index.theme" && -f /usr/share/icons/Papirus-Dark/index.theme ]] || return 1
    # Arch's package owns the GTK theme; never replace user theme directories.
    target="$USER_HOME_DIR/.themes/$theme"
    core_cli_parent_links_allowed "$target" || return 1
    if [[ -e "$target" || -L "$target" ]]; then
      [[ -L "$target" && "$(readlink "$target")" == "/usr/share/themes/$theme" ]] || {
        print_error_message "GTK theme source conflict: $target; preserved"; return 1;
      }
    else
      mkdir -p "$USER_HOME_DIR/.themes" && ln -s "/usr/share/themes/$theme" "$target" || return 1
    fi
    papirus-folders -C cat-mocha-lavender --theme Papirus-Dark || return 1
    return 0
  fi
  for target in "$USER_HOME_DIR/.themes/$theme" "$USER_HOME_DIR/.local/share/icons/Papirus" "$USER_HOME_DIR/.local/share/icons/Papirus-Dark"; do
    if ! core_cli_parent_links_allowed "$target" || ! appearance_link_allowed "$root" "$target"; then
      print_error_message "Appearance source conflict: $target; preserved"; return 1
    fi
  done
  ensure_native_pkgs papirus-icon-theme curl ca-certificates python3 || return $?
  dest="$(install_appearance_asset gtk-1.0.3 'https://github.com/catppuccin/gtk/releases/download/v1.0.3/catppuccin-mocha-lavender-standard%2Bdefault.zip' \
    bce962098f32c676a0170f909b737eed0905d53b6e774f04f152256b5b6dce77 gtk)" || return 1
  link_appearance_asset "$dest/$theme" "$USER_HOME_DIR/.themes/$theme" || return 1
  dest="$(install_appearance_asset papirus-f83671d https://codeload.github.com/catppuccin/papirus-folders/tar.gz/f83671d17ea67e335b34f8028a7e6d78bca735d7 \
    52105ae8a0b97ec6d6d9d3978f9ab7b4c274d9eb752e79c22fe30dc153cc2a5b papirus)" || return 1
  version="$(dpkg-query -W -f='${Version}' papirus-icon-theme)" || return 1
  [[ "$version" =~ ^[a-zA-Z0-9.+:~-]+$ ]] || return 1
  overlay="$root/papirus-overlay-$version-f83671d"
  core_cli_parent_links_allowed "$overlay" || return 1
  if [[ ! -e "$overlay" ]]; then
    stage="$(mktemp -d "$root/.papirus-XXXXXX")" || return 1
    if ! python3 "$DF_SCRIPT_DIR/appearance-assets.py" overlay "$dest" "$stage"; then rm -rf "$stage"; return 1; fi
    printf '%s\n' 'dotfiles-arch appearance' >"$stage/.dfa-appearance" || { rm -rf "$stage"; return 1; }
    mv -T "$stage" "$overlay" || { rm -rf "$stage"; return 1; }
  fi
  [[ ! -L "$overlay" && -O "$overlay" && -f "$overlay/.dfa-appearance" \
    && "$(cat "$overlay/.dfa-appearance")" == 'dotfiles-arch appearance' ]] || return 1
  link_appearance_asset "$overlay/Papirus" "$USER_HOME_DIR/.local/share/icons/Papirus" || return 1
  link_appearance_asset "$overlay/Papirus-Dark" "$USER_HOME_DIR/.local/share/icons/Papirus-Dark"
}
