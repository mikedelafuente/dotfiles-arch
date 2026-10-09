#!/usr/bin/env bash
# GPU decisions are separate from installation. PCI devices/ICDs are not readiness.
gpu_nvidia_package_kind() {
  case "$1:$2" in
    arch:nvidia|arch:nvidia-dkms|arch:nvidia-lts|arch:nvidia-open|arch:nvidia-open-dkms|arch:nvidia-open-lts|arch:nvidia-*xx-dkms)
      echo module ;;
    ubuntu:nvidia-driver-*|ubuntu:nvidia-dkms-*|ubuntu:nvidia-kernel-*|ubuntu:nvidia-open*|ubuntu:nvidia-headless-*|ubuntu:linux-modules-nvidia-*|ubuntu:linux-objects-nvidia-*|ubuntu:linux-signatures-nvidia-*)
      echo module ;;
    arch:nvidia-utils*|arch:nvidia-settings|arch:nvidia-*xx-utils|ubuntu:libnvidia-*|ubuntu:nvidia-utils*|ubuntu:nvidia-compute-utils*|ubuntu:xserver-xorg-video-nvidia*|ubuntu:cuda-drivers*)
      echo stack ;;
    *) return 1 ;;
  esac
}

gpu_installed_nvidia_packages() {
  local distro="${WORKSTATION_DISTRO:-}" packages package kind
  [[ -n "$distro" ]] || distro="$(detect_workstation_distro)" || return 1
  case "$distro" in
    arch) packages="$(pacman -Qq)" || return 1 ;;
    ubuntu)
      packages="$(dpkg-query -W -f='${binary:Package} ${db:Status-Eflag} ${db:Status-Status}\n')" || return 1
      packages="$(awk '$2 == "ok" && $3 == "installed" {sub(/:.*/, "", $1); print $1}' <<<"$packages")" ;;
    *) return 1 ;;
  esac
  while IFS= read -r package; do
    kind="$(gpu_nvidia_package_kind "$distro" "$package")" || continue
    [[ "${1:-all}" == all || "$kind" == module ]] || continue
    printf '%s\n' "$package"
  done <<<"$packages"
}

has_nvidia_packages() {
  local packages
  packages="$(gpu_installed_nvidia_packages)" || return 1
  [[ -n "$packages" ]]
}

nvidia_driver_packages() { gpu_installed_nvidia_packages modules; }

# A saved true or --install opts in. Existing stacks are never repaired/replaced.
nvidia_setup_selection() {
  case "$1" in arch|ubuntu) ;; *) return 1 ;; esac
  if [[ "$3" == true ]]; then echo preserve
  elif [[ "$2" != true || "$4" != true ]]; then echo skip
  else echo install; fi
}

# Only Ubuntu's hardware recommendation, not a third-party repository or a pin.
ubuntu_nvidia_recommendation() {
  awk '
    $1 == "driver" && $2 == ":" && $3 ~ /^nvidia-driver-[0-9]+(-server)?(-open)?$/ &&
      $4 == "-" && $5 == "distro" && $NF == "recommended" {name=$3; count++}
    END {if (count == 1) print name; else exit 1}
  ' <<<"$1"
}

# Open modules cannot drive pre-Turing GPUs. Unknown PCI chipset names defer
# selection instead of installing a potentially incompatible kernel driver.
gpu_nvidia_open_supported() {
  local line seen=false
  while IFS= read -r line; do
    [[ "$line" =~ (VGA|3D|Display).*NVIDIA|NVIDIA.*(VGA|3D|Display) ]] || continue
    [[ "$line" =~ (^|[[:space:]])(TU|GA|AD|GH|GB)[0-9]{3}[A-Z]*([[:space:]]|$) ]] || return 1
    seen=true
  done <<<"$1"
  [[ "$seen" == true ]]
}

# Official current Ollama support floor, supplied nvidia-smi CSV facts.
gpu_cuda_supported() {
  local driver compute major minor minimum
  while IFS=, read -r driver compute; do
    driver="${driver//[[:space:]]/}"
    compute="${compute//[[:space:]]/}"
    [[ "$compute" =~ ^([0-9]{1,2})\.([0-9])$ ]] || continue
    major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"
    ((10#$major >= 5)) || continue
    minimum=550.0.0
    if ((10#$major < 6 || (10#$major == 6 && 10#$minor <= 2))); then minimum=570.0.0; fi
    core_cli_version_at_least "$driver" "$minimum" && return 0
  done <<<"$1"
  return 1
}

# Check a real device and Vulkan 1.2+, excluding llvmpipe/lavapipe CPU devices.
gpu_vulkan_supported() {
  awk '
    /^GPU[0-9]+:/ {api=0}
    $1 == "apiVersion" && $2 == "=" {
      split($3, version, "."); api=(version[1] > 1 || (version[1] == 1 && version[2] >= 2))
    }
    $1 == "deviceType" && $2 == "=" && $3 ~ /PHYSICAL_DEVICE_TYPE_(DISCRETE|INTEGRATED)_GPU$/ && api {found=1}
    END {exit !found}
  ' <<<"$1"
}

# Read-only probes used by actual setup, never executed by the fixture checks.
has_working_cuda() {
  local facts
  command -v nvidia-smi >/dev/null && command -v python3 >/dev/null || return 1
  facts="$(nvidia-smi --query-gpu=driver_version,compute_cap --format=csv,noheader 2>/dev/null)" || return 1
  gpu_cuda_supported "$facts" || return 1
  # NVML success alone does not prove CUDA initializes with this user's permissions.
  python3 - <<'PY' >/dev/null 2>&1
import ctypes
import sys
try:
    cuda = ctypes.CDLL("libcuda.so.1")
    count = ctypes.c_int()
    sys.exit(0 if cuda.cuInit(0) == 0 and cuda.cuDeviceGetCount(ctypes.byref(count)) == 0 and count.value > 0 else 1)
except (OSError, AttributeError):
    sys.exit(1)
PY
}

has_working_vulkan() {
  local facts
  command -v vulkaninfo >/dev/null || return 1
  facts="$(LC_ALL=C vulkaninfo --summary 2>/dev/null)" || return 1
  gpu_vulkan_supported "$facts"
}

# Supplied existing backend facts. Preserve existing flavors even on mixed GPUs.
ollama_gpu_selection() {
  case "$1" in arch|ubuntu) ;; *) return 1 ;; esac
  case "$2" in
    none|upstream) ;;
    native)
      if [[ " $3 " == *' cuda '* && "$4" == true ]]; then echo cuda; return 0; fi
      if [[ " $3 " == *' vulkan '* && "$5" == true ]]; then echo vulkan; return 0; fi
      print_error_message 'Installed Ollama GPU flavor is not usable; retained. Check driver, runtime and device permissions.' >&2
      return 1 ;;
    *) print_error_message 'Ollama source/launcher conflict; existing installation retained' >&2; return 1 ;;
  esac
  if [[ "$4" == true ]]; then echo cuda
  elif [[ "$5" == true ]]; then echo vulkan
  elif [[ "$2" == none ]]; then echo skip
  else print_error_message 'Ollama GPU capability pending; retained. Check driver and device permissions.' >&2; return 1; fi
}

# Native Ubuntu packages need an actual repository candidate, not only a local DEB.
ollama_apt_owner_allowed() {
  awk '
    $1 == "Candidate:" {candidate=$2}
    $1 == "***" {selected=($2 == candidate); next}
    NF == 2 && $2 ~ /^[0-9]+$/ {selected=($1 == candidate); next}
    selected && $2 ~ /^(https?:\/\/|file:)/ {found=1}
    END {exit !found}
  ' <<<"$1"
}

ollama_user_unit() {
  cat <<'UNIT'
# dotfiles-arch: verified Ollama archive service
[Unit]
Description=Ollama local model server
After=network-online.target
[Service]
ExecStart="%h/.local/share/dotfiles-arch/editor-tools/ollama/current/bin/ollama" serve
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_VULKAN=1"
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
UNIT
}

# Do not adopt a vendor/IT unit, a mask, drop-ins, or custom user configuration.
ollama_user_service_allowed() {
  local unit="$USER_HOME_DIR/.config/systemd/user/ollama.service" directory parent
  parent="$(dirname "$unit")"
  while [[ "$parent" != / ]]; do
    [[ ! -L "$parent" && ( ! -e "$parent" || -d "$parent" ) ]] || return 1
    parent="$(dirname "$parent")"
  done
  [[ ! -e "$unit" && ! -L "$unit" ]] || { [[ ! -L "$unit" ]] && cmp -s "$unit" <(ollama_user_unit); } || return 1
  for directory in /etc/systemd/system /run/systemd/system /usr/lib/systemd/system /lib/systemd/system; do
    [[ ! -e "$directory/ollama.service" && ! -L "$directory/ollama.service" && ! -d "$directory/ollama.service.d" ]] || return 1
  done
  [[ ! -e "$USER_HOME_DIR/.config/systemd/user/ollama.service.d" \
    && ! -L "$USER_HOME_DIR/.config/systemd/user/ollama.service.d" ]]
}

ollama_runtime_backends() {
  local root="$1" backend_list=()
  [[ -d "$root" ]] || return 0
  if [[ -n "$(find "$root" \( -type f -o -type l \) -name 'libggml-cuda.so*' -print -quit)" ]]; then backend_list+=(cuda); fi
  if [[ -n "$(find "$root" \( -type f -o -type l \) -name 'libggml-vulkan.so*' -print -quit)" ]]; then backend_list+=(vulkan); fi
  [[ ${#backend_list[@]} -eq 0 ]] || printf '%s\n' "${backend_list[*]}"
}

ensure_ollama() {
  local root="$USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools/ollama"
  local unit="$USER_HOME_DIR/.config/systemd/user/ollama.service"
  local mode="${1:-setup}" previous='' owner=none backends='' launcher resolved cuda=false vulkan=false backend flavor policy path directory
  launcher="$(type -P ollama || true)"
  resolved="$(readlink -f "${launcher:-/nonexistent}" || true)"
  if [[ -e "$root" || -L "$root" ]]; then
    owner=upstream
    if native_package_installed ollama \
      || ! editor_upstream_layout_allowed ollama "$root" "$USER_HOME_DIR/.local/bin/ollama" \
      || [[ "$resolved" != "$(readlink -f "$root/current/bin/ollama")" ]]; then owner=unknown; fi
    [[ "$owner" != upstream ]] || previous="$(readlink "$root/current")" || return 1
  elif native_package_installed ollama; then
    owner=native
    [[ "$resolved" == /usr/bin/ollama ]] || owner=unknown
    if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
      policy="$(LC_ALL=C apt-cache policy ollama)" || return 1
      ollama_apt_owner_allowed "$policy" || owner=unknown
      backends="$(ollama_runtime_backends /usr/lib/ollama)" || return 1
    else
      native_package_installed ollama-cuda && backends+=' cuda'
      native_package_installed ollama-vulkan && backends+=' vulkan'
    fi
  elif [[ -n "$launcher" ]]; then owner=unknown; fi
  for path in /usr/local/bin/ollama /usr/bin/ollama /snap/bin/ollama "$USER_HOME_DIR/.local/bin/ollama"; do
    [[ ! -e "$path" && ! -L "$path" ]] && continue
    [[ -n "$launcher" && "$(readlink -f "$path")" == "$resolved" && "$owner" != none ]] || owner=unknown
  done
  [[ "$owner" != unknown ]] || { print_error_message 'Ollama source conflict; retained, resolve update ownership explicitly'; return 1; }
  if [[ "$owner" == native || ( "$owner" == none && "$WORKSTATION_DISTRO" == arch ) ]]; then
    for directory in /etc/systemd/system /run/systemd/system; do
      if [[ -e "$directory/ollama.service" || -L "$directory/ollama.service" || -e "$directory/ollama.service.d" ]]; then
        print_error_message 'Ollama native service conflict; custom units/configuration retained'; return 1
      fi
    done
    [[ ! -e "$unit" && ! -L "$unit" && ! -e "${unit}.d" ]] || {
      print_error_message 'Ollama user/system service conflict; existing configuration retained'; return 1;
    }
  fi
  if [[ "$owner" == upstream || ( "$owner" == none && "$WORKSTATION_DISTRO" == ubuntu ) ]]; then
    [[ "$EUID" -ne 0 ]] || { print_error_message 'Run user Ollama setup/update as the workstation user'; return 1; }
    ollama_user_service_allowed || { print_error_message 'Ollama service conflict; existing units/configuration retained'; return 1; }
    if [[ "$mode" == update ]]; then
      systemctl --user is-active --quiet ollama.service || {
        print_error_message 'Ollama user service pending/inactive; update will not enable a disabled service'; return 1;
      }
    fi
  fi
  # Probe tools do not install a GPU driver. A missing probe is not working Vulkan.
  if command -v nvidia-smi >/dev/null; then
    if [[ "$WORKSTATION_DISTRO" == arch ]]; then ensure_native_pkgs python; else ensure_native_pkgs python3; fi || return 1
  fi
  has_working_cuda && cuda=true
  if [[ "$cuda" != true || "$owner" == native ]]; then
    if compgen -G '/usr/share/vulkan/icd.d/*.json' >/dev/null; then
      ensure_native_pkgs vulkan-tools || return 1
    fi
    has_working_vulkan && vulkan=true
  fi
  backend="$(ollama_gpu_selection "$WORKSTATION_DISTRO" "$owner" "$backends" "$cuda" "$vulkan")" || return 1
  if [[ "$backend" == skip ]]; then
    print_info_message 'No working CUDA or hardware Vulkan 1.2+ backend; skipping Ollama (GPU-only policy)'
    return 0
  fi
  if [[ "$WORKSTATION_DISTRO" == arch && "$owner" == none ]]; then
    flavor="ollama-$backend"
    ensure_native_pkgs "$flavor" || return 1
    native_package_installed "$flavor" && native_package_installed ollama || return 1
    hash -r
    owner=native
  elif [[ "$WORKSTATION_DISTRO" == ubuntu || "$owner" == upstream ]]; then
    if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
      ensure_native_pkgs curl jq ca-certificates zstd python3 || return 1
    else
      ensure_native_pkgs curl jq ca-certificates zstd python || return 1
    fi
    ensure_editor_tool ollama || return 1
    if [[ -d "$root" ]]; then
      backends="$(ollama_runtime_backends "$root/current/lib/ollama")" || return 1
      [[ " $backends " == *" $backend "* ]] || { print_error_message "Ollama archive lacks $backend runtime; service retained"; return 1; }
      mkdir -p "$(dirname "$unit")" || return 1
      [[ -f "$unit" ]] || ollama_user_unit >"$unit" || return 1
      if [[ "$mode" == setup ]]; then
        systemctl --user daemon-reload && systemctl --user enable --now ollama.service || return 1
      fi
      if [[ -n "$previous" && "$previous" != "$(readlink "$root/current")" ]]; then
        systemctl --user restart ollama.service || return 1
      fi
      systemctl --user is-active --quiet ollama.service || {
        print_error_message 'Ollama user service failed/pending; inspect journalctl --user -u ollama. Check GPU device permissions; no groups/capabilities were changed.'
        return 1
      }
      print_info_message "Ollama $backend archive; dfa-update-system owns refreshes; user service enabled"
      return 0
    fi
  fi
  [[ "$(readlink -f "$(type -P ollama || true)")" == /usr/bin/ollama ]] || return 1
  path="$(editor_installed_version ollama /usr/bin/ollama)" || return 1
  core_cli_version_at_least "$path" 0.40.0 || {
    print_error_message 'Ollama requires 0.40.0+ for the selected current GPU runtimes; update its native owner (retained)'; return 1;
  }
  [[ ! -e "$unit" && ! -L "$unit" ]] || {
    print_error_message 'Ollama user/system service conflict; existing user unit retained'; return 1;
  }
  # Native units/configuration remain package-owned. Refuse custom units/overrides.
  path="$(systemctl show ollama.service -p FragmentPath --value)" || return 1
  case "$path" in /usr/lib/systemd/system/ollama.service|/lib/systemd/system/ollama.service) ;;
    *) print_error_message 'Ollama native service conflict/missing unit; preserved'; return 1 ;;
  esac
  [[ -z "$(systemctl show ollama.service -p DropInPaths --value)" ]] || {
    print_error_message 'Custom Ollama service overrides retained; enable/verify the service explicitly'; return 1;
  }
  case "$WORKSTATION_DISTRO" in
    arch) [[ "$(pacman -Qoq "$path")" == ollama ]] || return 1 ;;
    ubuntu)
      policy="$(dpkg-query -L ollama)" || return 1
      grep -Fxq -e "$path" -e "$(readlink -f "$path")" <<<"$policy" || return 1 ;;
  esac
  if [[ "$mode" == setup ]]; then sudo systemctl enable --now ollama.service || return 1; fi
  systemctl is-active --quiet ollama.service || {
    print_error_message 'Ollama system service failed/pending; inspect journalctl -u ollama and service-user GPU permissions'
    return 1
  }
  print_info_message "Ollama $backend native flavor retained; native packages own updates"
}

# Installed apps only; acquisition/service failures reach the common update stamp.
refresh_gpu_tools() {
  local root="$USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools/ollama"
  if [[ -e "$root" || -L "$root" ]] || command -v ollama >/dev/null || native_package_installed ollama; then
    ensure_ollama update || return 1
  fi
}
