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

# Canonical profile names in menu / display order.
# Multiple profiles can be active on one machine (e.g. work + devcontainer).
KNOWN_SETUP_PROFILES=(work personal devcontainer)

# Source saved bootstrap config if present
# (FULL_NAME, EMAIL, SETUP_PROFILES, SETUP_PROFILE, INSTALL_NVIDIA, MACHINE_TYPE,
# DEFAULT_AGENT).
load_bootstrap_config() {
  local f
  f="$(bootstrap_config_file)"
  if [[ -r "$f" ]]; then
    # shellcheck source=/dev/null
    source "$f"
    # Migrate legacy profile name (single) and multi-select
    if [[ "${SETUP_PROFILE:-}" == "productivity" ]]; then
      SETUP_PROFILE="work"
    fi
    migrate_setup_profiles_from_legacy
    return 0
  fi
  return 1
}

# Ensure SETUP_PROFILES is set from SETUP_PROFILE (legacy single value) when needed.
# Normalizes both; sets SETUP_PROFILE to primary for older readers.
migrate_setup_profiles_from_legacy() {
  local normalized primary
  if [[ -n "${SETUP_PROFILES:-}" ]]; then
    if normalized="$(normalize_setup_profiles "$SETUP_PROFILES")"; then
      SETUP_PROFILES="$normalized"
    else
      SETUP_PROFILES=""
    fi
  fi
  if [[ -z "${SETUP_PROFILES:-}" && -n "${SETUP_PROFILE:-}" ]]; then
    if normalized="$(normalize_setup_profiles "$SETUP_PROFILE")"; then
      SETUP_PROFILES="$normalized"
    fi
  fi
  if [[ -n "${SETUP_PROFILES:-}" ]]; then
    primary="$(primary_setup_profile)"
    SETUP_PROFILE="$primary"
  fi
}

# True if profile $1 is in the active SETUP_PROFILES list.
has_setup_profile() {
  local needle="${1:-}"
  local p
  [[ -z "$needle" ]] && return 1
  # shellcheck disable=SC2086
  for p in ${SETUP_PROFILES:-}; do
    [[ "$p" == "$needle" ]] && return 0
  done
  return 1
}

# Primary profile for single-value consumers (link label, Super+B preference).
# Prefer work when selected; otherwise first known profile that is active.
primary_setup_profile() {
  local p
  if has_setup_profile work; then
    echo "work"
    return 0
  fi
  for p in "${KNOWN_SETUP_PROFILES[@]}"; do
    if has_setup_profile "$p"; then
      echo "$p"
      return 0
    fi
  done
  echo "work"
}

# Space-separated → comma-separated for display / CLI examples.
format_setup_profiles() {
  local s="${1:-${SETUP_PROFILES:-}}"
  echo "${s// /,}"
}

# Validate SETUP_PROFILES is a non-empty set of known names. Returns 1 if invalid.
# Also keeps SETUP_PROFILE in sync as primary.
validate_bootstrap_profile() {
  migrate_setup_profiles_from_legacy
  if [[ -z "${SETUP_PROFILES:-}" ]]; then
    return 1
  fi
  if ! normalize_setup_profiles "$SETUP_PROFILES" >/dev/null; then
    return 1
  fi
  SETUP_PROFILE="$(primary_setup_profile)"
  return 0
}

# Write current identity/profile/NVIDIA/machine prefs (full rewrite of known keys).
# Values are shell-escaped so a sourced config cannot inject code via quotes/$().
# SETUP_PROFILES is canonical (space-separated multi-select); SETUP_PROFILE is primary (compat).
write_bootstrap_config() {
  local dir f primary
  dir="$(bootstrap_config_dir)"
  f="$(bootstrap_config_file)"
  migrate_setup_profiles_from_legacy
  if [[ -z "${SETUP_PROFILES:-}" ]]; then
    SETUP_PROFILES="work"
  fi
  primary="$(primary_setup_profile)"
  SETUP_PROFILE="$primary"
  mkdir -p "$dir"
  {
    echo "# Configuration file for dotfiles bootstrap script"
    printf 'FULL_NAME=%q\n' "${FULL_NAME:-}"
    printf 'EMAIL_ADDRESS=%q\n' "${EMAIL_ADDRESS:-}"
    printf 'SETUP_PROFILES=%q\n' "${SETUP_PROFILES}"
    printf 'SETUP_PROFILE=%q\n' "${SETUP_PROFILE}"
    printf 'INSTALL_NVIDIA=%q\n' "${INSTALL_NVIDIA:-false}"
    printf 'MACHINE_TYPE=%q\n' "${MACHINE_TYPE:-}"
    printf 'DEFAULT_AGENT=%q\n' "${DEFAULT_AGENT:-}"
  } >"$f"
  chmod 600 "$f" 2>/dev/null || true
}

# --------------------------
# Sync sources config (extra rules/skills repos)
# --------------------------

sync_sources_config_file() {
  echo "$(bootstrap_config_dir)/sync-sources"
}

# Normalize a repo path for comparison (stdout). Returns 1 if empty.
normalize_sync_source_repo_path() {
  local path="${1:-}"
  [[ -n "$path" ]] || return 1
  realpath -m "$path"
}

# Read every non-comment path from sync-sources into SYNC_SOURCE_REPO_LINES
# (normalized, deduped, file order). Does not check that paths exist.
_read_sync_source_repo_lines() {
  SYNC_SOURCE_REPO_LINES=()
  local f line normalized
  local -A seen=()
  f="$(sync_sources_config_file)"
  [[ -r "$f" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if ! normalized="$(normalize_sync_source_repo_path "$line")"; then
      continue
    fi
    if [[ -n "${seen[$normalized]:-}" ]]; then
      continue
    fi
    seen["$normalized"]=1
    SYNC_SOURCE_REPO_LINES+=("$normalized")
  done <"$f"
}

# Load extra sync source repos into SYNC_SOURCE_REPOS (existing dirs only).
load_sync_source_repos() {
  SYNC_SOURCE_REPOS=()
  local path
  _read_sync_source_repo_lines
  for path in "${SYNC_SOURCE_REPO_LINES[@]}"; do
    if [[ ! -d "$path" ]]; then
      print_warning_message "Sync source not found (skipping): $path"
      continue
    fi
    SYNC_SOURCE_REPOS+=("$path")
  done
}

# Write SYNC_SOURCE_REPOS array to sync-sources config.
write_sync_source_repos() {
  local dir f path
  dir="$(bootstrap_config_dir)"
  f="$(sync_sources_config_file)"
  mkdir -p "$dir"
  {
    echo "# Extra rules/skills source repos (one absolute path per line)"
    echo "# Managed by sync-sources add/remove — dotfiles-arch is always primary"
    for path in "${SYNC_SOURCE_REPOS[@]}"; do
      printf '%s\n' "$path"
    done
  } >"$f"
  chmod 600 "$f" 2>/dev/null || true
}

# Append a repo to sync-sources if not already listed. Returns 1 on error.
add_sync_source_repo() {
  local raw="${1:-}" normalized path
  [[ -n "$raw" ]] || return 1
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    return 1
  fi
  if [[ ! -d "$normalized" ]]; then
    print_error_message "Not a directory: $normalized"
    return 1
  fi
  SYNC_SOURCE_REPOS=()
  _read_sync_source_repo_lines
  SYNC_SOURCE_REPOS=("${SYNC_SOURCE_REPO_LINES[@]}")
  for path in "${SYNC_SOURCE_REPOS[@]}"; do
    if [[ "$path" == "$normalized" ]]; then
      print_info_message "Already listed: $normalized"
      return 0
    fi
  done
  SYNC_SOURCE_REPOS+=("$normalized")
  write_sync_source_repos
  if [[ ! -d "$normalized/rules" && ! -d "$normalized/skills" ]]; then
    print_warning_message "No rules/ or skills/ under $normalized — nothing to sync until you add them"
  fi
  print_success_message "Added sync source: $normalized"
  return 0
}

# Remove a repo from sync-sources. Returns 1 if it was not listed.
remove_sync_source_repo() {
  local raw="${1:-}" normalized path kept=() found=false
  [[ -n "$raw" ]] || return 1
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    return 1
  fi
  SYNC_SOURCE_REPOS=()
  _read_sync_source_repo_lines
  for path in "${SYNC_SOURCE_REPO_LINES[@]}"; do
    if [[ "$path" == "$normalized" ]]; then
      found=true
      continue
    fi
    kept+=("$path")
  done
  if [[ "$found" != true ]]; then
    print_warning_message "Not listed: $normalized"
    return 1
  fi
  SYNC_SOURCE_REPOS=("${kept[@]}")
  write_sync_source_repos
  print_success_message "Removed sync source: $normalized"
  return 0
}

# Populate SYNC_SOURCE_REPOS_ALL: primary dotfiles-arch root + configured extras.
collect_sync_source_repos() {
  local primary="${1:-}"
  SYNC_SOURCE_REPOS_ALL=()
  [[ -n "$primary" ]] && SYNC_SOURCE_REPOS_ALL+=("$primary")
  load_sync_source_repos
  SYNC_SOURCE_REPOS_ALL+=("${SYNC_SOURCE_REPOS[@]}")
}

# Given a resolved symlink target, print repo root if under …/rules/… or …/skills/….
sync_source_repo_root_from_resolved() {
  local resolved="${1:-}"
  [[ -n "$resolved" ]] || return 1
  case "$resolved" in
    */rules/*|*/skills/*)
      dirname "$(dirname "$resolved")"
      return 0
      ;;
  esac
  return 1
}

# Normalize a single profile token to work|personal|devcontainer (stdout).
# Maps productivity → work. Returns 1 if invalid.
# Prefer normalize_setup_profiles for multi-select CLI args.
normalize_setup_profile() {
  case "${1,,}" in
    1|work|productivity) echo "work" ;;
    2|personal) echo "personal" ;;
    3|devcontainer|dev-container|dev_container) echo "devcontainer" ;;
    *) return 1 ;;
  esac
}

# Normalize one or more profiles to a unique space-separated list in KNOWN_SETUP_PROFILES
# order (stdout). Accepts comma/space/plus-separated names or numbers (1 3, work,devcontainer).
# Returns 1 if empty or any token is invalid.
normalize_setup_profiles() {
  local raw="${1:-}"
  local -A selected=()
  local token normalized p out=""
  raw="${raw//+/ }"
  raw="${raw//,/ }"
  # shellcheck disable=SC2086
  for token in $raw; do
    [[ -z "$token" ]] && continue
    if ! normalized="$(normalize_setup_profile "$token")"; then
      return 1
    fi
    selected["$normalized"]=1
  done
  if [[ ${#selected[@]} -eq 0 ]]; then
    return 1
  fi
  for p in "${KNOWN_SETUP_PROFILES[@]}"; do
    if [[ -n "${selected[$p]:-}" ]]; then
      out+="${out:+ }$p"
    fi
  done
  echo "$out"
}

# Print multi-select profile menu lines (for bootstrap/sync prompts).
print_setup_profile_menu() {
  echo "  1) work         — Zoom + Slack + Chrome"
  echo "  2) personal     — Steam + Discord + Firefox + Mullvad"
  echo "  3) devcontainer — host tools for platform sandbox (just, mkcert, openvpn3, DNS, …)"
  echo "Select one or more (comma/space-separated numbers or names)."
  echo "Examples: 1,3   or   work,devcontainer   or   1 2 3"
}

# Normalize machine type input to laptop|desktop (stdout). Returns 1 if invalid.
normalize_machine_type() {
  case "${1,,}" in
    1|laptop|notebook|portable) echo "laptop" ;;
    2|desktop|workstation|tower|pc) echo "desktop" ;;
    *) return 1 ;;
  esac
}

# Resolve MACHINE_TYPE from saved value / battery detect / prompt.
# Uses ASSUME_YES=true|false (default false). Sets MACHINE_TYPE to laptop|desktop.
resolve_machine_type() {
  local assume_yes="${ASSUME_YES:-false}"
  local machine_default="desktop"
  local machine_input normalized

  if [[ "${MACHINE_TYPE:-}" == "laptop" || "${MACHINE_TYPE:-}" == "desktop" ]]; then
    if [[ "$assume_yes" == "true" ]]; then
      return 0
    fi
    echo ""
    print_info_message "Current MACHINE_TYPE: $(fmt_choice "$MACHINE_TYPE")"
    read -rp "Press Enter to keep MACHINE_TYPE=$(fmt_choice "$MACHINE_TYPE"), or type laptop/desktop: " machine_input
    case "${machine_input:-}" in
      "") ;; # Enter → keep
      *)
        if normalized="$(normalize_machine_type "$machine_input")"; then
          MACHINE_TYPE="$normalized"
        else
          print_warning_message "Unrecognized input '$machine_input'; keeping MACHINE_TYPE=$MACHINE_TYPE"
        fi
        ;;
    esac
    return 0
  fi

  if has_battery; then
    machine_default="laptop"
  fi

  if [[ "$assume_yes" == "true" ]]; then
    MACHINE_TYPE="$machine_default"
    print_info_message "MACHINE_TYPE not saved — auto-set to $MACHINE_TYPE (battery detect)"
    return 0
  fi

  echo ""
  print_info_message "Machine type drives power profile, lid behavior, and audio power saving."
  if has_battery; then
    print_info_message "Detected: battery present (looks like a laptop)"
  else
    print_info_message "Detected: no battery (looks like a desktop)"
  fi
  read -rp "Is this a laptop or desktop? [laptop/desktop] (Enter = $(fmt_choice "$machine_default")): " machine_input
  machine_input="${machine_input:-$machine_default}"
  if normalized="$(normalize_machine_type "$machine_input")"; then
    MACHINE_TYPE="$normalized"
  else
    print_warning_message "Unrecognized input '$machine_input'; using $machine_default"
    MACHINE_TYPE="$machine_default"
  fi
}

# True when this machine should use laptop power policy.
# Prefers saved MACHINE_TYPE; falls back to battery detection.
machine_is_laptop() {
  case "${MACHINE_TYPE:-}" in
    laptop) return 0 ;;
    desktop) return 1 ;;
    *) has_battery ;;
  esac
}

# Resolve INSTALL_NVIDIA from saved value / hardware / prompts.
# Uses ASSUME_YES=true|false (default false). Sets INSTALL_NVIDIA to true|false.
resolve_nvidia_preference() {
  local assume_yes="${ASSUME_YES:-false}"
  local nvidia_default="false"
  local default_label nvidia_input

  if [[ "${INSTALL_NVIDIA:-}" == "true" || "${INSTALL_NVIDIA:-}" == "false" ]]; then
    if [[ "$assume_yes" == "true" ]]; then
      return 0
    fi
    echo ""
    print_info_message "Current INSTALL_NVIDIA: $(fmt_choice "$INSTALL_NVIDIA")"
    read -rp "Press Enter to keep INSTALL_NVIDIA=$(fmt_choice "$INSTALL_NVIDIA"), or type true/false: " nvidia_input
    case "${nvidia_input,,}" in
      "") ;; # Enter → keep
      true|y|yes) INSTALL_NVIDIA="true" ;;
      false|n|no|0) INSTALL_NVIDIA="false" ;;
      *)
        print_warning_message "Unrecognized input '$nvidia_input'; keeping INSTALL_NVIDIA=$INSTALL_NVIDIA"
        ;;
    esac
    return 0
  fi

  if has_nvidia_packages || has_nvidia_hardware; then
    nvidia_default="true"
  fi

  if [[ "$assume_yes" == "true" ]]; then
    INSTALL_NVIDIA="$nvidia_default"
    print_info_message "INSTALL_NVIDIA not saved — auto-set to $INSTALL_NVIDIA (packages/hardware detect)"
    return 0
  fi

  echo ""
  print_info_message "NVIDIA drivers are optional (skip on AMD/Intel-only machines)."
  if has_nvidia_packages; then
    print_info_message "Detected: NVIDIA packages already installed (likely from archinstall)"
  fi
  if has_nvidia_hardware; then
    print_info_message "Detected: NVIDIA GPU on PCI bus"
  fi
  if [[ "$nvidia_default" == "true" ]]; then
    default_label="yes"
  else
    default_label="no"
  fi
  read -rp "Install/keep NVIDIA drivers on this machine? [y/n] (Enter = $(fmt_choice "$default_label")): " nvidia_input
  nvidia_input="${nvidia_input:-$nvidia_default}"
  case "${nvidia_input,,}" in
    y|yes|true) INSTALL_NVIDIA="true" ;;
    *) INSTALL_NVIDIA="false" ;;
  esac
}

# Resolve DEFAULT_AGENT (cursor|claude) — the agent `code` starts when run
# without --agent. Detects which agent CLIs are actually on PATH: auto-picks
# the only one installed, asks when both are present (Enter keeps the saved
# choice), and leaves DEFAULT_AGENT empty when neither is installed.
# Uses ASSUME_YES=true|false (default false).
resolve_default_agent() {
  local assume_yes="${ASSUME_YES:-false}"
  local have_claude=false have_cursor=false
  local current_default agent_input

  command -v claude &>/dev/null && have_claude=true
  { command -v cursor-agent &>/dev/null || command -v agent &>/dev/null; } && have_cursor=true

  if [[ "$have_claude" != "true" && "$have_cursor" != "true" ]]; then
    DEFAULT_AGENT=""
    return 0
  fi

  if [[ "$have_claude" == "true" && "$have_cursor" != "true" ]]; then
    DEFAULT_AGENT="claude"
    print_info_message "DEFAULT_AGENT auto-set to claude (Cursor Agent CLI not installed)"
    return 0
  fi

  if [[ "$have_cursor" == "true" && "$have_claude" != "true" ]]; then
    DEFAULT_AGENT="cursor"
    print_info_message "DEFAULT_AGENT auto-set to cursor (Claude CLI not installed)"
    return 0
  fi

  # Both installed — ask which `code` should default to.
  current_default="${DEFAULT_AGENT:-cursor}"
  if [[ "$current_default" != "cursor" && "$current_default" != "claude" ]]; then
    current_default="cursor"
  fi

  if [[ "$assume_yes" == "true" ]]; then
    DEFAULT_AGENT="$current_default"
    print_info_message "Both agent CLIs installed — DEFAULT_AGENT=$DEFAULT_AGENT (non-interactive)"
    return 0
  fi

  echo ""
  print_info_message "Both Cursor Agent and Claude Code CLIs are installed."
  read -rp "Which should 'code' use by default? [cursor/claude] (Enter = $(fmt_choice "$current_default")): " agent_input
  agent_input="${agent_input:-$current_default}"
  case "${agent_input,,}" in
    cursor) DEFAULT_AGENT="cursor" ;;
    claude) DEFAULT_AGENT="claude" ;;
    *)
      print_warning_message "Unrecognized input '$agent_input'; using $current_default"
      DEFAULT_AGENT="$current_default"
      ;;
  esac
}

# Record pacman/yay cooldown stamps (call only after a successful safe_system_upgrade).
record_system_upgrade_stamps() {
  local dir
  dir="$(bootstrap_config_dir)"
  mkdir -p "$dir"
  date +%s >"$dir/.last_pacman_update"
  date +%s >"$dir/.last_pacman_upgrade"
  date +%s >"$dir/.last_yay_update"
}

# True when any upgrade stamp is missing or older than 1 day (86400s).
system_upgrade_cooldown_expired() {
  local dir now age stamp
  dir="$(bootstrap_config_dir)"
  now="$(date +%s)"
  for stamp in .last_pacman_update .last_pacman_upgrade .last_yay_update; do
    age=$((now - $(cat "$dir/$stamp" 2>/dev/null || echo 0)))
    if [[ "$age" -ge 86400 ]]; then
      return 0
    fi
  done
  return 1
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

# Ensure [multilib] (and its Include) are uncommented in pacman.conf.
# Sets MULTILIB_CHANGED=true when the file was modified; false otherwise.
ensure_multilib_enabled() {
  local conf="${1:-/etc/pacman.conf}"
  export MULTILIB_CHANGED=false
  if [[ ! -f "$conf" ]]; then
    print_error_message "pacman.conf not found: $conf"
    return 1
  fi
  if grep -q '^\[multilib\]' "$conf"; then
    print_info_message "[multilib] is already enabled in $conf"
    return 0
  fi
  if grep -q '^#\[multilib\]' "$conf"; then
    sudo sed -i '/^#\[multilib\]/{ s/^#//; n; s/^#//; }' "$conf"
    print_info_message "[multilib] and its Include line have been uncommented in $conf"
    export MULTILIB_CHANGED=true
    return 0
  fi
  print_warning_message "[multilib] section not found in $conf"
  return 1
}

# --------------------------
# AUR hardening (Atomic Arch / supply-chain guards)
# --------------------------
# Known-IoC gate (not a full PKGBUILD audit). Scan before any yay -S / yay -Syu.

# Regex (ERE) matched case-insensitively against PKGBUILD and *.install files.
aur_ioc_regex() {
  printf '%s' \
    'atomic-lockfile|js-digest|lockfile-js|' \
    'npm[[:space:]]+install[[:space:]]+atomic|bun[[:space:]]+install[[:space:]]+js-digest|' \
    'curl[^|[:space:]]*\|[[:space:]]*(ba)?sh|wget[^|[:space:]]*\|[[:space:]]*(ba)?sh|' \
    'pipefail.*curl|/dev/tcp/|' \
    '[[:space:]]eval[[:space:]]|base64[[:space:]]+-d|base64[[:space:]]+--decode'
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

# Scan a directory of AUR sources (PKGBUILD, *.install, *.sh). Returns 1 if IoC hit
# or if no scanner (rg/grep) is available (fail closed).
aur_scan_dir() {
  local dir="$1"
  local label="${2:-$dir}"
  local hits=""
  local files=()

  if [[ ! -d "$dir" ]]; then
    print_error_message "AUR scan: directory missing ($dir)"
    return 1
  fi

  mapfile -d '' files < <(
    find "$dir" -maxdepth 2 -type f \( \
      -name PKGBUILD -o -name '*.install' -o -name '*.sh' -o -name '*.bash' \
    \) -print0 2>/dev/null
  )

  # No scannable files — nothing to match (fetch already succeeded).
  if [[ ${#files[@]} -eq 0 ]]; then
    return 0
  fi

  if command -v rg &>/dev/null; then
    # rg exits 1 when no matches; that is clean, not a scanner failure.
    hits="$(rg -n -i -e "$(aur_ioc_regex)" -- "${files[@]}" 2>/dev/null || true)"
  elif command -v grep &>/dev/null; then
    hits="$(grep -n -i -E "$(aur_ioc_regex)" -- "${files[@]}" 2>/dev/null || true)"
  else
    print_error_message "AUR scan: need rg or grep to scan $label (fail closed)"
    return 1
  fi

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

# Extract bare package names from .SRCINFO depends lines (strip version constraints).
aur_srcinfo_deps() {
  local dir="$1"
  local srcinfo="$dir/.SRCINFO"
  [[ -f "$srcinfo" ]] || return 0
  # Matches: depends = foo, depends = foo>=1, etc.
  awk '
    /^[[:space:]]*(depends|makedepends|checkdepends)[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "", $0)
      sub(/[<>=].*$/, "", $0)
      gsub(/[[:space:]]/, "", $0)
      if ($0 != "" && $0 !~ /^[a-zA-Z0-9@._+-]+$/) next
      if ($0 != "") print $0
    }
  ' "$srcinfo" | sort -u
}

# True when package is available from an official pacman sync DB (not AUR-only).
aur_is_official_pkg() {
  local pkg="$1"
  pacman -Si "$pkg" &>/dev/null
}

# Scan an AUR package and recurse into AUR-only dependencies (.SRCINFO).
# Caps: max depth 8, max 25 packages visited.
aur_scan_package_tree() {
  local root_pkg="$1"
  local -A visited=()
  local count=0
  local max_pkgs=25
  local max_depth=8

  _aur_scan_tree_rec() {
    local pkg="$1"
    local depth="$2"
    local tmp dep deps

    if [[ -n "${visited[$pkg]:-}" ]]; then
      return 0
    fi
    if [[ "$count" -ge "$max_pkgs" ]]; then
      print_error_message "AUR scan: exceeded max packages ($max_pkgs) while scanning $root_pkg"
      return 1
    fi
    if [[ "$depth" -gt "$max_depth" ]]; then
      print_error_message "AUR scan: exceeded max depth ($max_depth) at $pkg (root $root_pkg)"
      return 1
    fi

    visited[$pkg]=1
    count=$((count + 1))

    tmp="$(mktemp -d)"
    print_info_message "Scanning AUR package: $pkg (depth $depth)"
    if ! aur_fetch_pkgbuild "$pkg" "$tmp"; then
      rm -rf "$tmp"
      return 1
    fi
    if ! aur_scan_dir "$tmp" "$pkg"; then
      rm -rf "$tmp"
      return 1
    fi

    mapfile -t deps < <(aur_srcinfo_deps "$tmp")
    rm -rf "$tmp"

    for dep in "${deps[@]}"; do
      [[ -n "$dep" ]] || continue
      if aur_is_official_pkg "$dep"; then
        continue
      fi
      # Already installed from somewhere — still scan if AUR-sourced upgrade path
      _aur_scan_tree_rec "$dep" "$((depth + 1))" || return 1
    done
    return 0
  }

  _aur_scan_tree_rec "$root_pkg" 0
}

# Scan every package that yay would upgrade from the AUR (yay -Qua), including AUR deps.
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
  print_action_message "Scanning ${#pending[@]} pending AUR upgrade(s) (with AUR deps)"
  for pkg in "${pending[@]}"; do
    [[ -n "$pkg" ]] || continue
    aur_scan_package_tree "$pkg" || return 1
  done
  print_success_message "AUR upgrade scan clean"
  return 0
}

# Install yay from the AUR into a temp dir if missing (mktemp; IoC-scanned before makepkg).
ensure_yay_installed() {
  local tmp rc=0
  if command -v yay &>/dev/null; then
    return 0
  fi
  print_action_message "Installing yay from AUR"
  ensure_pacman_pkgs base-devel git
  tmp="$(mktemp -d)"
  if ! git clone https://aur.archlinux.org/yay.git "$tmp/yay"; then
    print_error_message "Failed to clone yay from AUR"
    rm -rf "$tmp"
    return 1
  fi
  if ! aur_scan_dir "$tmp/yay" "yay"; then
    rm -rf "$tmp"
    return 1
  fi
  if (cd "$tmp/yay" && makepkg -si --noconfirm); then
    print_success_message "yay installed: $(command -v yay)"
  else
    print_error_message "yay installation failed"
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# Install missing AUR packages via yay after IoC scan (package + AUR deps).
# Env: DOTFILES_AUR_ASSUME_YES=true → --noconfirm after scan passes (bootstrap/sync --yes).
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
    aur_scan_package_tree "$pkg" || return 1
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
