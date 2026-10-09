#!/usr/bin/env bash
# Dictation acquisition/backend decisions consume facts; setup owns mutations.
dictation_source_selection() {
  local distro="$1" app="$2" owner="$3" version="$4"
  case "$distro:$app" in arch:voxtype|ubuntu:voxtype|arch:dotool|ubuntu:dotool) ;; *) return 1 ;; esac
  case "$owner" in
    none)
      if [[ "$distro" == arch ]]; then echo aur
      elif [[ "$app" == voxtype ]]; then echo release
      else echo build; fi ;;
    native|release|build|aur)
      core_cli_version_at_least "$version" 0.0.0 || return 1
      echo "$owner" ;;
    *) print_error_message "$app source/launcher conflict; retained, resolve its update owner explicitly" >&2; return 1 ;;
  esac
}

# Recognized older owners may refresh; the resulting install must meet the floor.
dictation_version_supported() {
  local app="$1" version="$2" minimum
  case "$app" in voxtype) minimum=1.1.0 ;; dotool) minimum=1.6.0 ;; *) return 1 ;; esac
  core_cli_version_at_least "$version" "$minimum" || {
    print_error_message "$app requires $minimum+ after refresh; selected owner retained" >&2; return 1;
  }
}

# CUDA13's bundled ORT covers sm70..sm120a. Require every visible GPU to fit:
# ORT's default device must not silently land on an incompatible mixed card.
voxtype_cuda13_supported() {
  local driver compute major minor seen=false
  while IFS=, read -r driver compute; do
    driver="${driver//[[:space:]]/}"; compute="${compute//[[:space:]]/}"
    core_cli_version_at_least "$driver" 580.0.0 || return 1
    [[ "$compute" =~ ^([0-9]{1,2})\.([0-9])$ ]] || return 1
    major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
    ((10#$major >= 7 && (10#$major < 12 || (10#$major == 12 && 10#$minor == 0)))) || return 1
    seen=true
  done <<<"$1"
  [[ "$seen" == true ]]
}

voxtype_cuda12_supported() {
  local driver compute
  gpu_cuda_supported "$1" || return 1
  while IFS=, read -r driver compute; do
    compute="${compute//[[:space:]]/}"
    [[ "$compute" =~ ^[5-9]\.[0-9]$ ]] || return 1
  done <<<"$1"
}

# engine, CPU flags, working CUDA13 hardware, working Vulkan, chosen variant,
# working existing CUDA12 runtime. Preserve a user's compatible chosen backend.
voxtype_backend_selection() {
  local engine="$1" flags=" $2 " cuda13="$3" vulkan="$4" variant="$5" cuda12="$6" flag
  if [[ -z "$variant" || "$engine" == new ]]; then
    if [[ "$engine" == new && "$flags" == *' avx512f '* && "$cuda13" == true ]]; then
      variant=voxtype-onnx-cuda-13
    elif [[ "$engine" == parakeet ]]; then
      if [[ "$flags" == *' avx512f '* && "$cuda13" == true ]]; then variant=voxtype-onnx-cuda-13
      elif [[ "$flags" == *' avx512f '* ]]; then variant=voxtype-onnx-avx512
      else variant=voxtype-onnx-avx2; fi
    elif [[ "$engine" == new || "$engine" == whisper ]]; then
      if [[ "$flags" == *' avx2 '* && "$vulkan" == true ]]; then variant=voxtype-vulkan
      elif [[ "$flags" == *' avx512f '* ]]; then variant=voxtype-avx512
      elif [[ "$flags" == *' avx2 '* ]]; then variant=voxtype-avx2
      else variant=voxtype-baseline; fi
    else return 1; fi
  fi
  if [[ "$engine" != new ]]; then
    case "$engine:$variant" in
      whisper:voxtype-baseline|whisper:voxtype-avx2|whisper:voxtype-avx512|whisper:voxtype-vulkan|parakeet:voxtype-onnx-*) ;;
      *) print_error_message 'Voxtype engine/backend conflict; config retained, select a compatible variant explicitly' >&2; return 1 ;;
    esac
  fi
  case "$variant" in
    voxtype-baseline)
      for flag in sse4_2 ssse3 popcnt cx16 lahf_lm; do [[ "$flags" == *" $flag "* ]] || return 1; done ;;
    voxtype-avx2|voxtype-onnx-avx2) [[ "$flags" == *' avx2 '* ]] || return 1 ;;
    voxtype-avx512|voxtype-onnx-avx512) [[ "$flags" == *' avx512f '* ]] || return 1 ;;
    voxtype-vulkan) [[ "$flags" == *' avx2 '* && "$vulkan" == true ]] || return 1 ;;
    voxtype-onnx-cuda-13) [[ "$flags" == *' avx512f '* && "$cuda13" == true ]] || return 1 ;;
    voxtype-onnx-cuda-12) [[ "$flags" == *' avx512f '* && "$cuda12" == true ]] || return 1 ;;
    *) return 1 ;;
  esac
  echo "$variant"
}

# A known native repository can keep ownership. Local packages require either
# our verified build marker or the official Voxtype package identity.
# `verify` additionally enforces the installed minimum after acquisition/refresh.
dictation_app_owner() {
  local app="$1" package="$1" verify="${2:-}" path resolved owner=none version='' policy homepage files other selected
  [[ "$WORKSTATION_DISTRO:$app" != arch:voxtype ]] || package=voxtype-bin
  path="$(type -P "$app" || true)"
  if native_package_installed "$package"; then
    owner=unknown
    files=''
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then
      version="$(pacman -Q "$package")" || return 1
      version="${version#* }"
      [[ -n "$path" ]] || return 1
      resolved="$(readlink -f "$path")" || return 1
      if [[ "$app" == voxtype && "$resolved" == /usr/bin/voxtype ]]; then
        resolved="$(voxtype_dispatch_target "$path" || echo "$resolved")"
      fi
      [[ "$(pacman -Qoq "$resolved" 2>/dev/null)" == "$package" ]] || return 1
      owner=aur
    else
      version="$(dpkg-query -W -f='${Version}' "$package")" || return 1
      files="$(dpkg-query -L "$package")" || return 1
      [[ "$path" == "/usr/bin/$app" ]] || return 1
      grep -Fxq "$path" <<<"$files" || return 1
      policy="$(LC_ALL=C apt-cache policy "$package")" || return 1
      if ollama_apt_owner_allowed "$policy"; then
        if [[ "$app" == voxtype && ( -e /var/lib/dotfiles-arch/dictation/voxtype-source || -L /var/lib/dotfiles-arch/dictation/voxtype-source ) ]]; then
          print_error_message 'Voxtype release/repository owner conflict; existing source retained' >&2; return 1
        fi
        if [[ "$app" == dotool && -e /usr/share/doc/dotool/dfa-source ]]; then
          print_error_message 'dotool build/repository owner conflict; existing source retained' >&2; return 1
        fi
        owner=native
      elif [[ "$app" == voxtype ]]; then
        homepage="$(dpkg-query -W -f='${Homepage}' "$package")" || return 1
        [[ "$homepage" == https://voxtype.io || "$homepage" == https://github.com/peteonrails/voxtype ]] || return 1
        [[ "$(dpkg-query -W -f='${Maintainer}' "$package")" == 'Peter Jackson <pete@peteonrails.com>' ]] || return 1
        owner=release
      elif [[ -f /usr/share/doc/dotool/dfa-source && ! -L /usr/share/doc/dotool/dfa-source \
        && "$(cat /usr/share/doc/dotool/dfa-source)" == 'https://git.sr.ht/~geb/dotool' ]]; then owner=build; fi
    fi
    version="$(editor_package_version "$version")" || return 1
  elif [[ -n "$path" ]]; then owner=unknown; fi
  resolved="$(readlink -f "${path:-/nonexistent}" || true)"
  for other in "/usr/local/bin/$app" "/snap/bin/$app" "$USER_HOME_DIR/.local/bin/$app" "$USER_HOME_DIR/.cargo/bin/$app"; do
    [[ ! -e "$other" && ! -L "$other" ]] && continue
    if [[ -z "$path" || "$(readlink -f "$other")" != "$resolved" ]]; then owner=unknown; fi
  done
  selected="$(dictation_source_selection "$WORKSTATION_DISTRO" "$app" "$owner" "$version")" || return 1
  if [[ "$verify" == verify ]]; then dictation_version_supported "$app" "$version" || return 1; fi
  echo "$selected"
}

# AUR hooks generate an unowned dispatch wrapper. Accept only the canonical
# shell/exec form; ownership of its CUDA target is checked by the caller.
voxtype_dispatch_target() {
  local path="$1" dispatch
  [[ "$(head -n1 "$path")" == '#!/bin/sh' ]] || return 1
  dispatch="$(sed '/^#/d; /^[[:space:]]*$/d' "$path")" || return 1
  case "$dispatch" in
    'exec /usr/lib/voxtype/cuda-12/voxtype-onnx-cuda-12 "$@"'|'exec /usr/lib/voxtype/cuda-13/voxtype-onnx-cuda-13 "$@"')
      dispatch="${dispatch#exec }"; echo "${dispatch% \"\$@\"}" ;;
    *) return 1 ;;
  esac
}

# Resolve symlinks and upstream's canonical CUDA wrapper without running it.
voxtype_active_variant() {
  local path=/usr/bin/voxtype target
  if [[ -L "$path" ]]; then target="$(readlink -f "$path")" || return 1
  elif [[ -f "$path" ]]; then
    if grep -Fxq '# Voxtype CPU-adaptive wrapper script' "$path"; then
      target=/usr/lib/voxtype/voxtype-avx2
      if grep -qw avx512f /proc/cpuinfo; then target=/usr/lib/voxtype/voxtype-avx512; fi
    elif target="$(voxtype_dispatch_target "$path")"; then :
    else target="$(sed -n 's/^exec \(\/usr\/lib\/voxtype\/[^ ]*\) "\$@"$/\1/p' "$path")"; fi
  else return 1; fi
  [[ "$target" == /usr/lib/voxtype/* && -x "$target" ]] || return 1
  basename "$target"
}

# Do not replace custom units, masks or drop-ins. The package unit stays owned
# by its package; no `voxtype setup systemd` (which overwrites and masks errors).
voxtype_legacy_user_unit() {
  cat <<'UNIT'
[Unit]
Description=Voxtype push-to-talk voice-to-text daemon
Documentation=https://voxtype.io
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/voxtype daemon
Restart=on-failure
RestartSec=5

# Ensure we have access to the display
Environment=XDG_RUNTIME_DIR=%t

[Install]
WantedBy=graphical-session.target
UNIT
}

voxtype_service_allowed() {
  local fragment overrides directory="$USER_HOME_DIR/.config" user_unit
  [[ "${XDG_CONFIG_HOME:-}" != /* ]] || directory="$XDG_CONFIG_HOME"
  user_unit="$directory/systemd/user/voxtype.service"
  fragment="$(systemctl --user show voxtype.service -p FragmentPath --value)" || return 1
  overrides="$(systemctl --user show voxtype.service -p DropInPaths --value)" || return 1
  [[ -z "$overrides" ]] || return 1
  case "$fragment" in ''|/usr/lib/systemd/user/voxtype.service|/lib/systemd/user/voxtype.service) ;;
    *)
      if [[ "$fragment" == "$user_unit" && ! -L "$user_unit" ]] \
        && cmp -s "$user_unit" <(voxtype_legacy_user_unit); then return 0; fi
      print_error_message 'Custom/masked Voxtype service retained; manage and verify it explicitly'; return 1 ;;
  esac
}

voxtype_release_owner_allowed() {
  local marker="${1:-/var/lib/dotfiles-arch/dictation/voxtype-source}" parent
  parent="$(dirname "$marker")"
  while [[ "$parent" != / ]]; do
    [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || return 1
    parent="$(dirname "$parent")"
  done
  if [[ -e "$marker" || -L "$marker" ]]; then
    [[ -f "$marker" && ! -L "$marker" && "$(cat "$marker")" == 'https://github.com/peteonrails/voxtype' ]] || return 1
  fi
}

record_voxtype_release_owner() {
  local marker=/var/lib/dotfiles-arch/dictation/voxtype-source
  voxtype_release_owner_allowed "$marker" || return 1
  [[ ! -e "$marker" ]] || return 0
  sudo install -d -m 755 /var/lib/dotfiles-arch/dictation || return 1
  printf '%s\n' 'https://github.com/peteonrails/voxtype' | sudo tee "$marker" >/dev/null || return 1
}

install_voxtype_release() (
  local stage metadata fields version url digest installed='' held
  voxtype_release_owner_allowed /var/lib/dotfiles-arch/dictation/voxtype-source || { print_error_message 'Voxtype release-owner record conflict; retained'; return 1; }
  held="$(apt-mark showhold)" || return 1
  if grep -Fxq voxtype <<<"$held"; then print_info_message 'Voxtype installer policy-deferred: APT hold retained'; return 0; fi
  ensure_native_pkgs curl ca-certificates jq || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  metadata="$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL https://api.github.com/repos/peteonrails/voxtype/releases/latest)" || return 1
  fields="$(editor_release_asset voxtype "$metadata")" || return 1
  read -r version url digest <<<"$fields"
  if native_package_installed voxtype; then
    installed="$(dpkg-query -W -f='${Version}' voxtype)" || return 1
    if dpkg --compare-versions "$version-1" le "$installed"; then record_voxtype_release_owner; return $?; fi
  fi
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL "$url" -o "$stage/voxtype.deb" || return 1
  printf '%s  %s\n' "$digest" "$stage/voxtype.deb" | sha256sum -c - || return 1
  [[ "$(dpkg-deb -f "$stage/voxtype.deb" Package)" == voxtype \
    && "$(dpkg-deb -f "$stage/voxtype.deb" Version)" == "$version-1" \
    && "$(dpkg-deb -f "$stage/voxtype.deb" Architecture)" == amd64 ]] || return 1
  # Ensure the selected backend is actually shipped before touching the install.
  dpkg-deb --fsys-tarfile "$stage/voxtype.deb" | tar -tf - >"$stage/files" || return 1
  grep -Fxq "./usr/lib/voxtype/$VOXTYPE_SELECTED_VARIANT" "$stage/files" || return 1
  chmod 755 "$stage" || return 1
  chmod 644 "$stage/voxtype.deb" || return 1
  sudo apt-get install --yes --no-remove --no-install-recommends "$stage/voxtype.deb" || return 1
  record_voxtype_release_owner || return 1
)

# Reviewed source pin; build as the workstation user, stage a native local DEB.
# The package owns /usr/bin, its uinput rule and manpage; no dotoold service.
install_dotool_build() (
  local stage installed='' held pin=180af21c46dcc848d93dbec2644c011f4eea1592
  [[ "$EUID" -ne 0 && "$HOME" == "$USER_HOME_DIR" ]] || {
    print_error_message 'dotool source builds must run as the workstation user'; return 1;
  }
  held="$(apt-mark showhold)" || return 1
  if grep -Fxq dotool <<<"$held"; then print_info_message 'dotool build policy-deferred: APT hold retained'; return 0; fi
  if native_package_installed dotool; then
    installed="$(dpkg-query -W -f='${Version}' dotool)" || return 1
    if dpkg --compare-versions "$installed" ge 1.6-1dfa1; then return 0; fi
  fi
  ensure_native_pkgs curl ca-certificates build-essential golang-go libxkbcommon-dev pkg-config scdoc || return 1
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
    "https://git.sr.ht/~geb/dotool/archive/$pin.tar.gz" -o "$stage/source.tar.gz" || return 1
  printf '%s  %s\n' 960f83d4fa33f9d8a8b162663b4185a970a27f37d972d4496457eff6e0b6613c "$stage/source.tar.gz" | sha256sum -c - || return 1
  tar -xzf "$stage/source.tar.gz" --no-same-owner -C "$stage" || return 1
  cd "$stage/dotool-$pin" || return 1
  env GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOSUMDB=sum.golang.org GONOSUMDB='' GOPRIVATE='' \
    GONOPROXY='' GOPROXY=https://proxy.golang.org,direct DOTOOL_VERSION=1.6 sh ./build.sh || return 1
  env DOTOOL_DESTDIR="$stage/package" DOTOOL_BINDIR=usr/bin DOTOOL_UDEV_RULES_DIR=usr/lib/udev/rules.d sh ./build.sh install || return 1
  mkdir -p "$stage/package/DEBIAN" "$stage/package/usr/share/doc/dotool" || return 1
  printf '%s\n' 'https://git.sr.ht/~geb/dotool' >"$stage/package/usr/share/doc/dotool/dfa-source" || return 1
  cp LICENSE "$stage/package/usr/share/doc/dotool/copyright" || return 1
  cat >"$stage/package/DEBIAN/control" <<'DEB' || return 1
Package: dotool
Version: 1.6-1dfa1
Architecture: amd64
Maintainer: dotfiles-arch maintainer
Depends: libc6, libxkbcommon0
Homepage: https://git.sr.ht/~geb/dotool
Description: Wayland and X11 typing through Linux uinput
 Verified upstream source built and refreshed by dotfiles-arch.
DEB
  dpkg-deb --build --root-owner-group "$stage/package" "$stage/dotool.deb" || return 1
  chmod 755 "$stage" || return 1
  chmod 644 "$stage/dotool.deb" || return 1
  sudo apt-get install --yes --no-remove "$stage/dotool.deb" || return 1
)

# Limit NVIDIA's source to required runtime libraries/config dependencies. No
# driver, toolkit metapackage, cuDNN12 substitution or older Ubuntu source.
voxtype_cuda_pins() {
  cat <<'PINS'
Package: cuda-cudart-13-4 libcublas-13-4 libcufft-13-4 libcurand-13-4 libcudnn9-cuda-13 cuda-toolkit-config-common cuda-toolkit-13-config-common cuda-toolkit-13-4-config-common
Pin: origin developer.download.nvidia.com
Pin-Priority: 600

Package: *
Pin: origin developer.download.nvidia.com
Pin-Priority: -1
PINS
}

ensure_voxtype_cuda13() (
  local source pins=/etc/apt/preferences.d/dfa-voxtype-cuda stage file plan
  local packages=(cuda-cudart-13-4 libcublas-13-4 libcufft-13-4 libcurand-13-4 libcudnn9-cuda-13
    cuda-toolkit-config-common cuda-toolkit-13-config-common cuda-toolkit-13-4-config-common)
  if [[ "$WORKSTATION_DISTRO" == arch ]]; then ensure_native_pkgs cuda cudnn; return $?; fi
  source="$(work_app_apt_source voxtype-cuda)" || return 1
  if [[ -n "$source" && ! -e "$pins" && ! -L "$pins" ]]; then
    print_error_message 'Existing NVIDIA repository update policy retained; runtime-only pin requires explicit source resolution'; return 1
  fi
  stage="$(mktemp -d)" || return 1
  trap 'rm -rf "$stage"' EXIT
  voxtype_cuda_pins >"$stage/pins" || return 1
  if [[ -e "$pins" || -L "$pins" ]]; then
    if [[ -L "$pins" ]] || ! cmp -s "$pins" "$stage/pins"; then
      print_error_message 'NVIDIA runtime pin conflict; existing policy retained'; return 1;
    fi
  fi
  for file in /etc/apt/preferences /etc/apt/preferences.d/*; do
    [[ -f "$file" && "$file" != "$pins" ]] || continue
    if grep -qE 'developer\.download\.nvidia\.com|cuda|cudnn' "$file"; then
      print_error_message 'Existing CUDA/NVIDIA APT policy retained; resolve runtime source policy explicitly'; return 1
    fi
  done
  # Install the negative pin before exposing the vendor source to APT.
  sudo install -d -m 755 /etc/apt/preferences.d || return 1
  sudo install -m 644 "$stage/pins" "$pins" || return 1
  ensure_work_app_apt_source voxtype-cuda "$source" || return 1
  sudo apt-get update --error-on=any || return 1
  plan="$(LC_ALL=C apt-get --simulate install --no-remove --no-install-recommends "${packages[@]}")" || return 1
  python3 "$DF_SCRIPT_DIR/dictation_metadata.py" cuda-plan "$plan" || return 1
  sudo apt-get install --yes --no-remove --no-install-recommends "${packages[@]}" || return 1
)

voxtype_runtime_ready() {
  python3 "$DF_SCRIPT_DIR/dictation_metadata.py" runtime "$1" "/usr/lib/voxtype/$1"
}

dotool_rules_allowed() {
  local file files
  for file in /etc/udev/rules.d/80-dotool.rules /run/udev/rules.d/80-dotool.rules; do
    if [[ -e "$file" || -L "$file" ]]; then
      print_error_message "Custom dotool permission rule retained: $file; resolve its policy explicitly"; return 1
    fi
  done
  file=/usr/lib/udev/rules.d/80-dotool.rules
  if [[ -e "$file" || -L "$file" ]]; then
    native_package_installed dotool || return 1
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then [[ "$(pacman -Qoq "$file")" == dotool ]] || return 1
    else
      files="$(dpkg-query -L dotool)" || return 1
      grep -Fxq "$file" <<<"$files" || return 1
    fi
  fi
}

# A managed CUDA source must retain its runtime-only pin before ordinary APT
# upgrades can see it. An external matching runtime needs no source migration.
check_voxtype_cuda_source() {
  local pins=/etc/apt/preferences.d/dfa-voxtype-cuda source
  [[ -e "$pins" || -L "$pins" ]] || return 0
  if [[ -L "$pins" ]] || ! cmp -s "$pins" <(voxtype_cuda_pins); then
    print_error_message 'Managed NVIDIA runtime pin changed; restore runtime-only policy explicitly before updating'; return 1
  fi
  source="$(work_app_apt_source voxtype-cuda)" || return 1
  [[ -n "$source" ]] || { print_error_message 'Managed CUDA runtime source missing; existing policy retained'; return 1; }
}

# Capture selection before the native upgrade can replace /usr/bin/voxtype.
check_dictation_owners() {
  local app
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then check_voxtype_cuda_source || return 1; fi
  for app in voxtype dotool; do
    if command -v "$app" >/dev/null || native_package_installed "$app" \
      || { [[ "$app" == voxtype && "$WORKSTATION_DISTRO" == arch ]] && native_package_installed voxtype-bin; }; then
      if ! dictation_app_owner "$app" >/dev/null; then
        print_error_message "$app source/launcher/version conflict; retained, resolve its update owner explicitly"; return 1
      fi
    fi
  done
  VOXTYPE_UPDATE_VARIANT=''
  VOXTYPE_UPDATE_FILESTAMP=''
  VOXTYPE_UPDATE_ACTIVE=false
  if command -v voxtype >/dev/null; then
    [[ "$EUID" -ne 0 ]] || { print_error_message 'Run dictation updates as the workstation user'; return 1; }
    voxtype_service_allowed || return 1
    VOXTYPE_UPDATE_VARIANT="$(voxtype_active_variant)" || return 1
    VOXTYPE_UPDATE_FILESTAMP="$(stat -c '%Y:%s' /usr/lib/voxtype/"$VOXTYPE_UPDATE_VARIANT")" || return 1
    if systemctl --user is-active --quiet voxtype.service; then VOXTYPE_UPDATE_ACTIVE=true; fi
  fi
}

# Standalone setup refreshes incompatible packages through the recognized owner.
# Ordinary updates already ran the native/AUR upgrade; never bypass its policy.
ensure_dictation_app() {
  local app="$1" owner="$2" mode="$3" package="$1"
  [[ "$WORKSTATION_DISTRO:$app" != arch:voxtype ]] || package=voxtype-bin
  case "$owner" in
    aur)
      ensure_yay_installed || return 1
      if [[ "$mode" == setup ]] && native_package_installed "$package" \
        && ! dictation_app_owner "$app" verify >/dev/null 2>&1; then
        ensure_yay_pkgs --refresh "$package" || return 1
      else ensure_yay_pkgs "$package" || return 1; fi ;;
    native)
      if [[ "$mode" == setup ]] && ! dictation_app_owner "$app" verify >/dev/null 2>&1; then
        sudo apt-get update --error-on=any || return 1
        [[ "$(dictation_app_owner "$app")" == native ]] || return 1
        sudo apt-get install --yes --no-remove --no-install-recommends "$package" || return 1
      fi ;;
    release) install_voxtype_release || return 1 ;;
    build) install_dotool_build || return 1 ;;
    *) return 1 ;;
  esac
  hash -r
  dictation_app_owner "$app" verify >/dev/null
}

ensure_voxtype() {
  local mode="$1" voxtype_owner dotool_owner flags facts='' cuda13=false cuda12=false vulkan=false
  local config_dir="$USER_HOME_DIR/.config" config engine=new variant='' model fresh=false active=false root_home version_before='' version_after
  [[ "${XDG_CONFIG_HOME:-}" != /* ]] || config_dir="$XDG_CONFIG_HOME"
  config="$config_dir/voxtype/config.toml"
  [[ "$EUID" -ne 0 && "$USER_HOME_DIR" == "$HOME" ]] || {
    print_error_message 'Run Voxtype setup/update as the workstation user; root must not own user models/config/service'; return 1;
  }
  voxtype_service_allowed || return 1
  dotool_rules_allowed || return 1
  if [[ "$mode" == setup ]]; then
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then ensure_native_pkgs python jq
    else ensure_native_pkgs python3 jq; fi || return 1
    python3 "$DF_SCRIPT_DIR/dictation_metadata.py" paths "$USER_HOME_DIR" || return 1
    if compgen -G '/usr/share/vulkan/icd.d/*.json' >/dev/null; then ensure_native_pkgs vulkan-tools || return 1; fi
  fi
  voxtype_owner="$(dictation_app_owner voxtype)" || { print_error_message 'Voxtype source/launcher/version conflict; retained'; return 1; }
  dotool_owner="$(dictation_app_owner dotool)" || { print_error_message 'dotool source/launcher/version conflict; retained'; return 1; }
  if [[ -e "$config" || -L "$config" ]]; then
    engine="$(python3 "$DF_SCRIPT_DIR/dictation_metadata.py" config "$config")" || return 1
  elif [[ -e /etc/voxtype/config.toml || -L /etc/voxtype/config.toml ]]; then
    config=/etc/voxtype/config.toml
    engine="$(python3 "$DF_SCRIPT_DIR/dictation_metadata.py" config "$config")" || return 1
  elif [[ "$mode" == setup ]]; then fresh=true
  else print_error_message 'Voxtype config missing; update retained, run standalone setup as your user'; return 1; fi
  if command -v voxtype >/dev/null; then
    if [[ -n "${VOXTYPE_UPDATE_VARIANT:-}" ]]; then variant="$VOXTYPE_UPDATE_VARIANT"
    else variant="$(voxtype_active_variant)" || return 1; fi
    if [[ -n "${VOXTYPE_UPDATE_FILESTAMP:-}" ]]; then version_before="$VOXTYPE_UPDATE_FILESTAMP"
    else version_before="$(stat -c '%Y:%s' /usr/lib/voxtype/"$variant")" || return 1; fi
  fi
  active="${VOXTYPE_UPDATE_ACTIVE:-false}"
  if [[ "$mode" == setup ]] && systemctl --user is-active --quiet voxtype.service; then active=true; fi
  flags="$(sed -n '/^flags[[:space:]]*:/{s/^flags[[:space:]]*:[[:space:]]*//;p;q;}' /proc/cpuinfo)" || return 1
  if has_working_cuda; then
    facts="$(nvidia-smi --query-gpu=driver_version,compute_cap --format=csv,noheader)" || return 1
    if voxtype_cuda13_supported "$facts"; then cuda13=true; fi
    if [[ "$variant" == voxtype-onnx-cuda-12 ]] && voxtype_cuda12_supported "$facts" \
      && voxtype_runtime_ready voxtype-onnx-cuda-12; then cuda12=true; fi
  fi
  has_working_vulkan && vulkan=true
  VOXTYPE_SELECTED_VARIANT="$(voxtype_backend_selection "$engine" "$flags" "$cuda13" "$vulkan" "$variant" "$cuda12")" || {
    print_error_message 'Voxtype backend unsupported/pending: check CPU ISA, working GPU, CUDA ABI and existing engine; config retained'; return 1;
  }
  if [[ "$VOXTYPE_SELECTED_VARIANT" == voxtype-vulkan ]]; then
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then ensure_native_pkgs vulkan-icd-loader
    else ensure_native_pkgs libvulkan1; fi || return 1
  fi
  ensure_dictation_app voxtype "$voxtype_owner" "$mode" || return 1
  ensure_dictation_app dotool "$dotool_owner" "$mode" || return 1
  [[ -x /usr/lib/voxtype/"$VOXTYPE_SELECTED_VARIANT" ]] || return 1
  if [[ "$VOXTYPE_SELECTED_VARIANT" == voxtype-onnx-cuda-13 ]] \
    && ! voxtype_runtime_ready "$VOXTYPE_SELECTED_VARIANT"; then ensure_voxtype_cuda13 || return 1; fi
  voxtype_runtime_ready "$VOXTYPE_SELECTED_VARIANT" || return 1
  # Explicit stable CLI variant selection does not regenerate user services.
  # Isolate privileged HOME even though this subcommand currently writes only
  # the package launcher; a plain CUDA symlink would break ORT provider lookup.
  root_home="$(mktemp -d)" || return 1
  if ! sudo env HOME="$root_home" XDG_CONFIG_HOME="$root_home/config" XDG_DATA_HOME="$root_home/data" \
    XDG_CACHE_HOME="$root_home/cache" XDG_STATE_HOME="$root_home/state" XDG_RUNTIME_DIR="$root_home/runtime" \
    "/usr/lib/voxtype/$VOXTYPE_SELECTED_VARIANT" setup variant --to "$VOXTYPE_SELECTED_VARIANT"; then
    rm -rf "$root_home"; return 1
  fi
  rm -rf "$root_home"
  if [[ "$mode" == setup ]]; then
    if [[ "$fresh" == true ]]; then
      mkdir -p "$(dirname "$config")" || return 1
      engine=whisper; model=base.en
      if [[ "$VOXTYPE_SELECTED_VARIANT" == voxtype-onnx-cuda-13 ]]; then engine=parakeet; model=parakeet-tdt-0.6b-v3; fi
      cat >"$config" <<EOF || return 1
# dotfiles-arch: GNOME Super+T toggle; existing files are never rewritten.
engine = "$engine"
[hotkey]
enabled = false
[output]
mode = "type"
driver_order = ["dotool", "clipboard"]
[$engine]
model = "$model"
EOF
      # Only an initial config fetches a model, never an installer refresh.
      /usr/bin/voxtype setup --download --model "$model" --no-post-install || return 1
    fi
    python3 "$DF_SCRIPT_DIR/dictation_metadata.py" model "$config" "$USER_HOME_DIR" || return 1
    if [[ ! -w /dev/uinput ]]; then
      print_error_message "dotool needs writable /dev/uinput; upstream rule uses input group (all keyboard devices). Run sudo usermod -aG input $(id -un), log out/in; check uinput/rules. No permissions were changed automatically."
      return 1
    fi
    if [[ "$fresh" == true ]]; then
      systemctl --user daemon-reload || return 1
      systemctl --user enable --now voxtype.service || return 1
      systemctl --user is-active --quiet voxtype.service || return 1
    elif [[ "$active" == false ]]; then
      print_info_message 'Voxtype service remains inactive/disabled; start explicitly with systemctl --user enable --now voxtype.service'
    fi
  fi
  version_after="$(stat -c '%Y:%s' /usr/lib/voxtype/"$VOXTYPE_SELECTED_VARIANT")" || return 1
  if [[ "$active" == true && ( "$variant" != "$VOXTYPE_SELECTED_VARIANT" || "$version_before" != "$version_after" ) ]]; then
    systemctl --user restart voxtype.service || return 1
    systemctl --user is-active --quiet voxtype.service || return 1
  fi
  print_info_message "Voxtype $VOXTYPE_SELECTED_VARIANT: $voxtype_owner; dotool: $dotool_owner. Updates never fetch models or activate disabled services."
}

refresh_dictation() {
  if command -v voxtype >/dev/null || native_package_installed voxtype \
    || { [[ "$WORKSTATION_DISTRO" == arch ]] && native_package_installed voxtype-bin; }; then
    ensure_voxtype update || return 1
  elif native_package_installed dotool; then
    local owner
    owner="$(dictation_app_owner dotool)" || return 1
    ensure_dictation_app dotool "$owner" update || return 1
  fi
}
