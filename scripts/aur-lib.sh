#!/usr/bin/env bash
# AUR hardening helpers (Atomic Arch / supply-chain guards).
# Known-IoC gate (not a full PKGBUILD audit). Scan before any yay -S / yay -Syu.
# Expects fn-lib.sh (print_*) to be loaded. Sourced by fn-lib.sh itself, since
# its ensure_yay_installed / ensure_yay_pkgs / safe_system_upgrade call into
# these — every script that sources dotheader.sh (fn-lib.sh) gets these
# functions transitively, including scripts/update-system.sh.

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
