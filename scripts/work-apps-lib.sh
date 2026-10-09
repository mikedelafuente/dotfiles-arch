#!/usr/bin/env bash
# Work-app source decisions consume supplied facts, never launch desktop apps.
# distro, app, selected-package-installed, package-owned-launcher, alternate-source, apt-source-state
work_app_selection() {
  local distro="$1" app="$2" installed="$3" launcher="$4" alternate="$5" source="$6" package owner
  case "$distro:$app" in
    arch:chrome) package=google-chrome; owner=aur ;;
    arch:slack) package=slack-desktop; owner=aur ;;
    arch:zoom) package=zoom; owner=aur ;;
    ubuntu:chrome) package=google-chrome-stable; owner=apt ;;
    ubuntu:slack) package=slack-desktop; owner=apt ;;
    ubuntu:zoom) package=zoom; owner=vendor-deb ;;
    arch:tableplus) package=tableplus; owner=aur ;;
    arch:spotify) package=spotify; owner=aur ;;
    ubuntu:tableplus) package=tableplus; owner=apt ;;
    ubuntu:spotify) package=spotify-client; owner=apt ;;
    *) return 1 ;;
  esac
  if [[ "$alternate" != false || ( -n "$launcher" && "$installed" != true ) \
    || "$source" == conflict || "$source" == unknown \
    || ( "$distro" == ubuntu && "$owner" == apt && "$installed" == true && "$source" != apt ) ]]; then
    print_error_message "Source/ownership conflict: $app; installation and settings preserved" >&2
    return 1
  fi
  [[ "$installed" == true || "$installed" == false ]] || return 1
  if [[ "$installed" == true && -z "$launcher" ]]; then
    print_error_message "Missing package launcher: $app; preserved" >&2; return 1
  fi
  case "$launcher" in ''|owned) ;; *)
    print_error_message "Launcher ownership conflict: $app; preserved" >&2; return 1 ;;
  esac
  [[ "$source" == none || "$source" == apt ]] || return 1
  [[ "$app" != zoom || "$distro" != ubuntu || "$source" == none ]] || return 1
  printf '%s %s\n' "$package" "$owner"
}

work_app_package_version() {
  python3 "$DF_SCRIPT_DIR/work_app_metadata.py" package-version "$1" "$2"
}

work_app_apt_candidate() {
  python3 "$DF_SCRIPT_DIR/work_app_metadata.py" apt-candidate "$1" "$2"
}

work_app_apt_key() {
  python3 "$DF_SCRIPT_DIR/work_app_metadata.py" apt-key "$1" "$2"
}

# Output an existing source and its scoped key, or nothing when absent.
# Optional root is only for read-only fixture checks.
work_app_apt_source() {
  local app="$1" root="${2:-/etc/apt}" pattern file key found=''
  case "$app" in
    chrome) pattern='dl(-ssl)?\.google\.com/linux/chrome' ;;
    slack) pattern='packagecloud\.io/slacktechnologies/slack|packages\.slack-edge\.com' ;;
    zoom) pattern='zoom\.(us|com)' ;;
    tableplus) pattern='(deb|apt)\.tableplus\.com' ;;
    spotify) pattern='(repository|download)\.spotify\.com' ;;
    mullvad) pattern='repository\.mullvad\.net' ;;
    firefox) pattern='packages\.mozilla\.org|mozillateam' ;;
    voxtype-cuda) pattern='developer\.download\.nvidia\.com/compute/cuda/repos' ;;
    *) return 1 ;;
  esac
  local files=("$root/sources.list")
  shopt -s nullglob
  files+=("$root"/sources.list.d/*.list "$root"/sources.list.d/*.sources)
  shopt -u nullglob
  for file in "${files[@]}"; do
    [[ -e "$file" || -L "$file" ]] || continue
    [[ -r "$file" ]] || { print_error_message "Unreadable APT source: $file" >&2; return 1; }
    grep -qE "$pattern" "$file" || continue
    if [[ -n "$found" || -L "$file" || "$app" == zoom ]]; then
      print_error_message "Duplicate/alternate $app source: $file; preserved" >&2; return 1
    fi
    key="$(work_app_apt_key "$app" "$(cat "$file")")" || return 1
    found="$file $key"
  done
  [[ -z "$found" ]] || printf '%s\n' "$found"
  return 0
}

work_app_fingerprint() {
  case "$1" in
    chrome) echo EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796 ;;
    slack) echo DB085A08CA13B8ACB917E0F6D938EC0D038651BD ;;
    zoom) echo 84C365D6CC9A4886CA926BCC4F2197399706AC24 ;;
    tableplus) echo 211438D2880D8D98E100B1412A17818B38772786 ;;
    spotify) echo E1096BCBFF6D418796DE78515384CE82BA52C83A ;;
    mullvad) echo A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF ;;
    firefox) echo 35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3 ;;
    voxtype-cuda) echo 14BAFBC7562AD710CA04E69905FBB6DA60DF8A40 ;;
    *) return 1 ;;
  esac
}

# Import only a pinned vendor primary key into an isolated staging keyring.
stage_work_app_key() {
  local app="$1" stage="$2" input="${3:-}" url fingerprint
  fingerprint="$(work_app_fingerprint "$app")" || return 1
  mkdir -m 700 "$stage/gnupg" || return 1
  if [[ -z "$input" ]]; then
    case "$app" in
      chrome) url=https://dl.google.com/linux/linux_signing_key.pub ;;
      slack) url=https://packagecloud.io/slacktechnologies/slack/gpgkey ;;
      zoom) url=https://zoom.us/linux/download/pubkey ;;
      tableplus) url=https://deb.tableplus.com/apt.tableplus.com.gpg.key ;;
      spotify) url=https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc ;;
      mullvad) url=https://repository.mullvad.net/deb/mullvad-keyring.asc ;;
      firefox) url=https://packages.mozilla.org/apt/repo-signing-key.gpg ;;
      voxtype-cuda) url=https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/60DF8A40.pub ;;
    esac
    input="$stage/key.download"
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$url" -o "$input" || return 1
  fi
  [[ -f "$input" && ! -L "$input" ]] || { print_error_message "$app key conflict; preserved"; return 1; }
  gpg --homedir "$stage/gnupg" --batch --show-keys --with-colons "$input" >"$stage/key-info" || return 1
  [[ "$(awk -F: '$1 == "pub" {n++} $1 == "fpr" && !seen++ {f=$10} END {if (n == 1) print f}' "$stage/key-info")" == "$fingerprint" ]] || {
    print_error_message "$app signing key fingerprint mismatch; preserved"; return 1;
  }
  gpg --homedir "$stage/gnupg" --batch --import "$input" || return 1
  gpg --homedir "$stage/gnupg" --batch --export "$fingerprint" >"$stage/key.gpg" || return 1
}

ensure_work_app_apt_source() (
  local app="$1" existing="$2" source key stage input=''
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  if [[ -n "$existing" ]]; then
    read -r source key <<<"$existing"
    input="$key"
  else
    case "$app" in
      chrome)
        source=/etc/apt/sources.list.d/google-chrome.sources
        key=/usr/share/keyrings/google-chrome.gpg
        cat >"$stage/source" <<EOF
X-Repolib-Name: Google Chrome
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: $key
EOF
        ;;
      slack)
        source=/etc/apt/sources.list.d/slack.list
        key=/usr/share/keyrings/slack.gpg
        printf 'deb [arch=amd64 signed-by=%s] https://packagecloud.io/slacktechnologies/slack/debian/ jessie main\n' "$key" >"$stage/source" ;;
      mullvad)
        source=/etc/apt/sources.list.d/mullvad.list
        key=/usr/share/keyrings/mullvad-keyring.gpg
        printf 'deb [arch=amd64 signed-by=%s] https://repository.mullvad.net/deb/stable stable main\n' "$key" >"$stage/source" ;;
      voxtype-cuda)
        source=/etc/apt/sources.list.d/dfa-voxtype-cuda.list
        key=/usr/share/keyrings/dfa-voxtype-cuda.gpg
        printf 'deb [arch=amd64 signed-by=%s] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/ /\n' "$key" >"$stage/source" ;;
      tableplus|spotify)
        source="/etc/apt/sources.list.d/$app.list"
        key="/usr/share/keyrings/$app.gpg"
        if [[ "$app" == tableplus ]]; then
          printf 'deb [arch=amd64 signed-by=%s] https://deb.tableplus.com/debian/26 tableplus main\n' "$key" >"$stage/source"
        else
          printf 'deb [arch=amd64 signed-by=%s] https://repository.spotify.com stable non-free\n' "$key" >"$stage/source"
        fi ;;
      *) return 1 ;;
    esac
    [[ ! -e "$source" && ! -L "$source" ]] || { print_error_message "$app source destination conflict; preserved"; return 1; }
    if [[ -e "$key" || -L "$key" ]]; then input="$key"; fi
  fi
  ensure_native_pkgs curl ca-certificates gnupg || return $?
  stage_work_app_key "$app" "$stage" "$input" || return 1
  if [[ -z "$existing" ]]; then
    sudo install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d || return 1
    [[ -n "$input" ]] || sudo install -m 644 "$stage/key.gpg" "$key" || return 1
    sudo install -m 644 "$stage/source" "$source" || return 1
  fi
)

# Gather installed facts separately from the pure selection seam.
work_app_installed_selection() {
  local app="$1" package installed=false launcher='' alternate=false source=none sources='' command path resolved selection snap_name
  local commands=()
  selection="$(work_app_selection "$WORKSTATION_DISTRO" "$app" false '' false none)" || return 1
  read -r package _ <<<"$selection"
  native_package_installed "$package" && installed=true
  case "$app" in
    chrome) commands=(google-chrome-stable google-chrome) ;;
    slack) commands=(slack) ;;
    zoom) commands=(zoom) ;;
    tableplus) commands=(tableplus) ;;
    spotify) commands=(spotify) ;;
  esac
  for command in "${commands[@]}"; do
    path="$(type -P "$command" || true)"
    [[ -n "$path" ]] || continue
    resolved="$(readlink -f "$path")" || return 1
    if [[ "$installed" == true ]] && {
      if [[ "$WORKSTATION_DISTRO" == arch ]]; then
        [[ "$(pacman -Qqo "$resolved" 2>/dev/null)" == "$package" ]]
      else
        dpkg-query -L "$package" | grep -Fx "$resolved" >/dev/null
      fi
    }; then
      launcher=owned
    else
      launcher=unknown; break
    fi
  done
  if command -v snap &>/dev/null; then
    local snaps
    snaps="$(snap list 2>/dev/null)" || { print_error_message 'Cannot inspect Snap ownership'; return 1; }
    case "$app" in chrome) snap_name=google-chrome ;; slack) snap_name=slack ;; zoom) snap_name=zoom-client ;; tableplus|spotify) snap_name="$app" ;; esac
    if printf '%s\n' "$snaps" | awk '{print $1}' | grep -Fxq "$snap_name"; then alternate=true; fi
  fi
  if command -v flatpak &>/dev/null; then
    local flatpaks
    flatpaks="$(flatpak list --app --columns=application)" || return 1
    case "$app" in
      chrome) command=com.google.Chrome ;;
      slack) command=com.slack.Slack ;;
      zoom) command=us.zoom.Zoom ;;
      tableplus) command=com.tableplus.TablePlus ;;
      spotify) command=com.spotify.Client ;;
    esac
    if printf '%s\n' "$flatpaks" | grep -Fxq "$command"; then alternate=true; fi
  fi
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    sources="$(work_app_apt_source "$app")" || return 1
    [[ -z "$sources" ]] || source=apt
    # Honor an existing update opt-out instead of silently recreating repositories.
    if [[ ( "$app" == chrome || "$app" == slack ) && -z "$sources" && -e "/etc/default/$( [[ "$app" == chrome ]] && echo google-chrome || echo slack )" ]]; then
      source=conflict
    fi
  fi
  work_app_selection "$WORKSTATION_DISTRO" "$app" "$installed" "$launcher" "$alternate" "$source"
}

install_zoom_deb() (
  local stage version installed held
  held="$(apt-mark showhold)" || return 1
  if printf '%s\n' "$held" | grep -Fxq zoom; then
    print_info_message 'Zoom update policy-deferred: APT hold retained'; return 0
  fi
  ensure_native_pkgs curl ca-certificates gnupg binutils python3 || return $?
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  stage_work_app_key zoom "$stage" || return 1
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
    https://zoom.us/client/latest/zoom_amd64.deb -o "$stage/zoom.deb" || return 1
  # Authenticate the embedded dpkg-sig manifest, then check every archive member.
  ar p "$stage/zoom.deb" _gpgbuilder >"$stage/signature" || return 1
  gpg --homedir "$stage/gnupg" --batch --status-fd 3 --decrypt "$stage/signature" \
    3>"$stage/status" >"$stage/manifest" || return 1
  grep -qF "[GNUPG:] VALIDSIG $(work_app_fingerprint zoom) " "$stage/status" || return 1
  python3 "$DF_SCRIPT_DIR/work_app_metadata.py" zoom-manifest "$stage/zoom.deb" "$stage/manifest" || return 1
  [[ "$(dpkg-deb -f "$stage/zoom.deb" Package)" == zoom \
    && "$(dpkg-deb -f "$stage/zoom.deb" Architecture)" == amd64 ]] || return 1
  version="$(dpkg-deb -f "$stage/zoom.deb" Version)" || return 1
  work_app_package_version zoom "$version" >/dev/null || return 1
  if native_package_installed zoom; then
    installed="$(dpkg-query -W -f='${Version}' zoom)" || return $?
    if dpkg --compare-versions "$version" gt "$installed"; then
      : # Install a newer verified release.
    else
      local comparison_status=$?
      [[ "$comparison_status" == 1 ]] && return 0
      return "$comparison_status"
    fi
  fi
  chmod 755 "$stage" || return 1
  chmod 644 "$stage/zoom.deb" || return 1
  sudo apt-get install --yes --no-remove "$stage/zoom.deb" || return $?
  native_package_installed zoom || return 1
)

ensure_work_app() {
  local app="$1" package owner sources selection
  selection="$(work_app_installed_selection "$app")" || return 1
  read -r package owner <<<"$selection"
  if [[ "$owner" == aur ]]; then
    if ! native_package_installed "$package"; then
      ensure_yay_installed || return $?
      ensure_yay_pkgs "$package" || return $?
    fi
  elif [[ "$owner" == apt ]]; then
    sources="$(work_app_apt_source "$app")" || return 1
    ensure_work_app_apt_source "$app" "$sources" || return 1
    sudo apt-get update --error-on=any || return $?
    work_app_apt_candidate "$app" "$(apt-cache policy "$package")" >/dev/null || return 1
    ensure_native_pkgs "$package" || return $?
    work_app_apt_source "$app" >/dev/null || return 1
  else
    install_zoom_deb || return 1
  fi
  native_package_installed "$package" || return 1
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    work_app_package_version "$app" "$(dpkg-query -W -f='${Version}' "$package")" >/dev/null || return 1
  fi
  work_app_installed_selection "$app" >/dev/null || return 1
  print_info_message "$app update owner: $owner; installation/desktop runtime unverified"
}

# Validate ownership before APT changes; Zoom alone needs a standalone refresh.
check_work_app_owners() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package sources key stage
  for app in chrome slack zoom; do
    case "$app" in chrome) package=google-chrome-stable ;; slack) package=slack-desktop ;; zoom) package=zoom ;; esac
    native_package_installed "$package" || continue
    work_app_installed_selection "$app" >/dev/null || return 1
    if [[ "$app" != zoom ]]; then
      sources="$(work_app_apt_source "$app")" || return 1
      read -r _ key <<<"$sources"
      stage="$(mktemp -d)" || return 1
      if ! stage_work_app_key "$app" "$stage" "$key"; then
        rm -rf "$stage"; return 1
      fi
      rm -rf "$stage"
    fi
  done
}

refresh_work_apps() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  check_work_app_owners || return 1
  if native_package_installed zoom; then install_zoom_deb || return 1; fi
  local app package selection
  for app in chrome slack zoom; do
    selection="$(work_app_selection ubuntu "$app" false '' false none)" || return 1
    read -r package _ <<<"$selection"
    native_package_installed "$package" || continue
    work_app_package_version "$app" "$(dpkg-query -W -f='${Version}' "$package")" >/dev/null || return 1
  done
}

# Fresh APT metadata must still select the vendor, even with third-party pins/sources.
check_work_app_candidates() {
  [[ "$WORKSTATION_DISTRO" == ubuntu ]] || return 0
  local app package
  for app in chrome slack; do
    case "$app" in chrome) package=google-chrome-stable ;; slack) package=slack-desktop ;; esac
    native_package_installed "$package" || continue
    work_app_apt_candidate "$app" "$(apt-cache policy "$package")" >/dev/null || return 1
  done
}
