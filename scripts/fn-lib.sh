#!/usr/bin/env bash
# --------------------------
# fn-lib.sh - A library of reusable bash functions for Arch setup scripts
# --------------------------

print_tool_setup_start() {
  local tool_name="$1"
  print_line_break "Starting setup for $tool_name"
}

print_tool_setup_complete() {
  local tool_name="$1"
  print_line_break "Completed setup for $tool_name"
}

# Function to print a green line break with an optional title
print_line_break() {
  local title="$1"
  echo -e "\e[32m--------------------------------------------------\e[0m"
  if [ -n "$title" ]; then
    # get the current time and date and print it along with the title
    local datetime
    datetime=$(date '+%Y-%m-%d %H:%M:%S.%N')
    echo -e "\e[32m$title | $datetime\e[0m"
    echo -e "\e[32m--------------------------------------------------\e[0m"
  fi
}

# Function to print an info message in blue
print_info_message() {
  local message="$1"
  echo -e "\e[34m$message\e[0m"
}   

# Function to print an action message in orange
print_action_message() {
  local message="$1"
  echo -e "\e[38;5;208m$message\e[0m"
}

print_success_message() {
  local message="$1"
  echo -e "\e[32m$message\e[0m"
}

# Function to print a warning message in yellow
print_warning_message() {
  local message="$1"
  echo -e "\e[33m$message\e[0m"
}

# Function to print an error message in red
print_error_message() {
  local message="$1"
  echo -e "\e[31m$message\e[0m"
}

# Turquoise highlight for the current/default choice in interactive prompts (no newline).
fmt_choice() {
  printf '\e[38;5;44m%s\e[0m' "$1"
}

# True when an NVIDIA GPU is visible to the system (PCI).
has_nvidia_hardware() {
  if command -v lspci &>/dev/null; then
    lspci -nn 2>/dev/null | grep -qiE 'NVIDIA.*(VGA|3D|Display)|VGA.*NVIDIA|3D.*NVIDIA|Display.*NVIDIA'
    return $?
  fi
  # Fallback: sysfs vendor ID 10de = NVIDIA
  local vendor
  for vendor in /sys/bus/pci/devices/*/vendor; do
    [[ -r "$vendor" ]] || continue
    if [[ "$(cat "$vendor" 2>/dev/null)" == "0x10de" ]]; then
      return 0
    fi
  done
  return 1
}

# True when an Arch NVIDIA driver stack is present (any common flavor).
has_nvidia_packages() {
  local pkg
  for pkg in \
    nvidia-open \
    nvidia-open-dkms \
    nvidia \
    nvidia-dkms \
    nvidia-lts \
    nvidia-open-lts \
    nvidia-utils
  do
    if pacman -Q "$pkg" &>/dev/null; then
      return 0
    fi
  done
  return 1
}

# Print installed NVIDIA driver module package name(s), if any (not utils-only).
nvidia_driver_packages() {
  local pkg
  for pkg in \
    nvidia-open \
    nvidia-open-dkms \
    nvidia \
    nvidia-dkms \
    nvidia-lts \
    nvidia-open-lts
  do
    if pacman -Q "$pkg" &>/dev/null; then
      echo "$pkg"
    fi
  done
}

# --------------------------
# Bootstrap config
# --------------------------

bootstrap_config_dir() {
  echo "${USER_HOME_DIR:-$HOME}/.config/dotfiles-arch"
}

bootstrap_config_file() {
  echo "$(bootstrap_config_dir)/.dotfiles_bootstrap_config"
}

# Source saved bootstrap config if present (FULL_NAME, EMAIL, SETUP_PROFILE, INSTALL_NVIDIA).
load_bootstrap_config() {
  local f
  f="$(bootstrap_config_file)"
  if [[ -r "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    # Migrate legacy profile name
    if [[ "${SETUP_PROFILE:-}" == "productivity" ]]; then
      SETUP_PROFILE="work"
    fi
    return 0
  fi
  return 1
}

# Validate / normalize SETUP_PROFILE. Returns 1 if unset/invalid.
validate_bootstrap_profile() {
  case "${SETUP_PROFILE:-}" in
    work|personal) return 0 ;;
    productivity)
      SETUP_PROFILE="work"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Write current identity/profile/NVIDIA prefs (preserves unknown keys by rewrite).
write_bootstrap_config() {
  local dir f
  dir="$(bootstrap_config_dir)"
  f="$(bootstrap_config_file)"
  mkdir -p "$dir"
  {
    echo "FULL_NAME=\"${FULL_NAME:-}\""
    echo "EMAIL_ADDRESS=\"${EMAIL_ADDRESS:-}\""
    echo "SETUP_PROFILE=\"${SETUP_PROFILE:-work}\""
    echo "INSTALL_NVIDIA=\"${INSTALL_NVIDIA:-false}\""
  } >"$f"
}

# --------------------------
# Hardware helpers
# --------------------------

# True when a Battery power_supply device exists (laptop).
has_battery() {
  local d
  for d in /sys/class/power_supply/*; do
    [[ -e "$d" ]] || continue
    [[ -r "$d/type" ]] || continue
    if [[ "$(cat "$d/type" 2>/dev/null)" == "Battery" ]]; then
      return 0
    fi
  done
  return 1
}

# True when Intel CPU and/or Intel PCI devices are present.
has_intel_hardware() {
  if grep -qi 'GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    return 0
  fi
  if command -v lspci &>/dev/null; then
    lspci -nn 2>/dev/null | grep -qi 'Intel'
    return $?
  fi
  return 1
}

# --------------------------
# Package helpers
# --------------------------

# Install missing pacman packages (idempotent). Usage: ensure_pacman_pkgs pkg1 pkg2 ...
ensure_pacman_pkgs() {
  local pkg
  local missing=()
  for pkg in "$@"; do
    if pacman -Q "$pkg" &>/dev/null; then
      print_info_message "Already installed: $pkg"
    else
      missing+=("$pkg")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi
  print_action_message "Installing via pacman: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}"
}

# --------------------------
# AUR hardening (Atomic Arch / supply-chain guards)
# --------------------------
# Known IoCs from the June 2026 "Atomic Arch" AUR campaign and common
# PKGBUILD footguns. Scan before any yay -S / yay -Syu.

# Regex (ERE) matched case-insensitively against PKGBUILD and *.install files.
aur_ioc_regex() {
  printf '%s' \
    'atomic-lockfile|js-digest|lockfile-js|' \
    'npm[[:space:]]+install[[:space:]]+atomic|bun[[:space:]]+install[[:space:]]+js-digest|' \
    'curl[^|[:space:]]*\|[[:space:]]*(ba)?sh|wget[^|[:space:]]*\|[[:space:]]*(ba)?sh|' \
    'pipefail.*curl|/dev/tcp/'
}

# Fetch AUR package sources into DIR (shallow clone). Returns 0 on success.
aur_fetch_pkgbuild() {
  local pkg="$1"
  local dest="$2"
  rm -rf "$dest"
  mkdir -p "$dest"
  if git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$dest" 2>/dev/null; then
    return 0
  fi
  # Fallback: raw PKGBUILD only
  if curl -fsSL "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=${pkg}" -o "$dest/PKGBUILD"; then
    return 0
  fi
  print_error_message "Could not fetch AUR sources for: $pkg"
  return 1
}

# Scan a directory of AUR sources (PKGBUILD, *.install, *.sh). Returns 1 if IoC hit.
aur_scan_dir() {
  local dir="$1"
  local label="${2:-$dir}"
  local hits
  if [[ ! -d "$dir" ]]; then
    print_error_message "AUR scan: directory missing ($dir)"
    return 1
  fi
  hits="$(
    find "$dir" -maxdepth 2 -type f \( \
      -name PKGBUILD -o -name '*.install' -o -name '*.sh' -o -name '*.bash' \
    \) -print0 2>/dev/null \
      | xargs -0 rg -n -i -e "$(aur_ioc_regex)" 2>/dev/null || true
  )"
  if [[ -n "$hits" ]]; then
    print_error_message "AUR SECURITY: suspicious content in $label"
    echo "$hits" >&2
    print_error_message "Refusing to install/upgrade. Inspect: https://aur.archlinux.org/packages/$label"
    return 1
  fi
  return 0
}

# Fetch + scan one AUR package by name.
aur_scan_package() {
  local pkg="$1"
  local tmp rc=0
  tmp="$(mktemp -d)"
  print_info_message "Scanning AUR package: $pkg"
  if ! aur_fetch_pkgbuild "$pkg" "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  if ! aur_scan_dir "$tmp" "$pkg"; then
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# Scan every package that yay would upgrade from the AUR (yay -Qua).
aur_scan_pending_upgrades() {
  local pkg
  local pending=()
  if ! command -v yay &>/dev/null; then
    return 0
  fi
  mapfile -t pending < <(yay -Qua 2>/dev/null | awk '{print $1}' || true)
  if [[ ${#pending[@]} -eq 0 ]]; then
    print_info_message "No pending AUR upgrades to scan"
    return 0
  fi
  print_action_message "Scanning ${#pending[@]} pending AUR upgrade(s)"
  for pkg in "${pending[@]}"; do
    [[ -n "$pkg" ]] || continue
    aur_scan_package "$pkg" || return 1
  done
  print_success_message "AUR upgrade scan clean"
  return 0
}

# Install missing AUR packages via yay after IoC scan.
# Env: DOTFILES_AUR_ASSUME_YES=true → --noconfirm after scan passes (bootstrap/sync).
ensure_yay_pkgs() {
  local pkg
  local missing=()
  local assume_yes="${DOTFILES_AUR_ASSUME_YES:-false}"
  if ! command -v yay &>/dev/null; then
    print_error_message "yay is required but not installed"
    return 1
  fi
  for pkg in "$@"; do
    if pacman -Q "$pkg" &>/dev/null; then
      print_info_message "Already installed: $pkg"
    else
      missing+=("$pkg")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  print_action_message "AUR install candidates: ${missing[*]}"
  for pkg in "${missing[@]}"; do
    aur_scan_package "$pkg" || return 1
  done

  if [[ "$assume_yes" == "true" || "$assume_yes" == "1" ]]; then
    print_warning_message "DOTFILES_AUR_ASSUME_YES set — installing with --noconfirm after clean IoC scan"
    yay -S --needed --noconfirm "${missing[@]}"
  else
    print_info_message "IoC scan clean. Running interactive yay (review PKGBUILD if prompted)."
    yay -S --needed "${missing[@]}"
  fi
}

# Guarded full system update: pacman -Syu + AUR scan + yay -Syu.
# Usage: safe_system_upgrade [--yes]
safe_system_upgrade() {
  local assume_yes=false
  local arg
  for arg in "$@"; do
    case "$arg" in
      --yes|-y) assume_yes=true ;;
    esac
  done

  print_line_break "Guarded system update"

  print_action_message "Updating official repositories (pacman -Syu)"
  if [[ "$assume_yes" == true ]]; then
    sudo pacman -Syu --noconfirm
  else
    sudo pacman -Syu
  fi

  if ! command -v yay &>/dev/null; then
    print_warning_message "yay not installed — skipping AUR upgrades"
    return 0
  fi

  print_action_message "Checking for AUR updates"
  if ! aur_scan_pending_upgrades; then
    print_error_message "Aborting AUR upgrade due to failed security scan"
    return 1
  fi

  print_action_message "Upgrading AUR packages (yay -Sua / -Syu AUR side)"
  if [[ "$assume_yes" == true ]]; then
    export DOTFILES_AUR_ASSUME_YES=true
    # -Syu after pacman already refreshed; -a limits to AUR if supported
    yay -Syu --noconfirm
  else
    yay -Syu
  fi

  print_success_message "Guarded system update complete"
}

# Remove orphaned packages if any (safe when none — pacman -Qtdq exits 1).
remove_orphaned_packages() {
  local orphans
  orphans="$(pacman -Qtdq 2>/dev/null || true)"
  if [[ -z "$orphans" ]]; then
    print_info_message "No orphaned packages found"
    return 0
  fi
  print_action_message "Removing orphaned packages: $orphans"
  # shellcheck disable=SC2086
  sudo pacman -Rns --noconfirm $orphans
}

# --------------------------
# NVM / Node
# --------------------------

# Canonical NVM location (matches home/.bashrc).
nvm_dir() {
  echo "${USER_HOME_DIR:-$HOME}/.config/nvm"
}

# Load nvm into the current shell. Migrates ~/.nvm → ~/.config/nvm once if needed.
# Returns 0 when nvm.sh was sourced.
load_nvm() {
  local dir legacy
  dir="$(nvm_dir)"
  legacy="${USER_HOME_DIR:-$HOME}/.nvm"

  if [[ ! -s "$dir/nvm.sh" && -s "$legacy/nvm.sh" ]]; then
    print_info_message "Migrating NVM from $legacy → $dir"
    mkdir -p "$(dirname "$dir")"
    mv "$legacy" "$dir"
  fi

  export NVM_DIR="$dir"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    return 0
  fi
  return 1
}

# --------------------------
# Fonts
# --------------------------

refresh_font_cache() {
  if command -v fc-cache &>/dev/null; then
    print_info_message "Refreshing font cache (fc-cache)"
    fc-cache -f >/dev/null || print_warning_message "fc-cache reported an error"
  fi
}
