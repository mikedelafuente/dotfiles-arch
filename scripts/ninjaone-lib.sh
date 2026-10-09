#!/usr/bin/env bash
# --------------------------
# ninjaone-lib.sh - helpers shared by setup-ninjaone.sh and update-ninjaone.sh
# --------------------------
# Source after dotheader.sh. The installer URL embeds the org's ClientUID, so it is
# a credential: it lives only in NINJAONE_ENV_FILE (mode 600, outside the repo) and
# is never printed — messages show the host and version only.

set +x # Credential handling must not inherit shell tracing.

NINJAONE_PKG="ninjaone-agent"
NINJAONE_OWNER_FILE="/var/lib/dotfiles-arch/ninjaone-package"
NINJAONE_BIN="/opt/NinjaRMMAgent/programfiles/ninjarmm-linagent"
NINJAONE_AGENT_CONF="/opt/NinjaRMMAgent/programfiles/config/agent.conf"
# Keep in sync with depends in ninjaone/PKGBUILD.
# shellcheck disable=SC2034
NINJAONE_RUNTIME_DEPS=(dmidecode dpkg inetutils lsof)
NINJAONE_PKG_DIR="$DF_SCRIPT_DIR/ninjaone"

ninjaone_env_file() {
  echo "$(bootstrap_config_dir)/ninjaone.env"
}

# Loads NINJAONE_INSTALLER_URL from the env file unless the environment already sets it.
ninjaone_load_url() {
  local f saved_url="${NINJAONE_INSTALLER_URL:-}"
  f="$(ninjaone_env_file)"
  # shellcheck source=/dev/null
  if [[ -r "$f" ]]; then
    [[ -f "$f" && ! -L "$f" && "$(stat -c '%u %a' "$f")" == "$(id -u) 600" ]] || {
      print_error_message "Saved NinjaOne credential must be a user-owned regular file with mode 600" >&2
      return 1
    }
    source "$f"
  fi
  [[ -n "$saved_url" ]] && NINJAONE_INSTALLER_URL="$saved_url"
  NINJAONE_INSTALLER_URL="${NINJAONE_INSTALLER_URL:-}"
}

ninjaone_save_url() {
  local url="$1" f staged
  ninjaone_url_valid "$url" || return 1
  f="$(ninjaone_env_file)"
  mkdir -p "$(dirname "$f")" || return 1
  staged="$(mktemp "$(dirname "$f")/.ninjaone.env.XXXXXX")" || return 1
  (
    umask 077
    {
      echo "# NinjaOne installer URL (credential - never commit)"
      printf 'NINJAONE_INSTALLER_URL=%q\n' "$url"
      printf 'NINJAONE_INSTALLER_VERSION=%q\n' "$(ninjaone_url_version "$url")"
    } >"$staged"
  ) || { rm -f "$staged"; return 1; }
  mv -fT "$staged" "$f"
}

# https://<region>.ninjarmm.com/agent/installer/<uid>/<version>/<name>.deb
ninjaone_url_valid() {
  [[ "$1" =~ ^https://[a-z0-9]+([.-][a-z0-9]+)*\.(ninjarmm|rmmservice)\.com/agent/installer/[A-Za-z0-9_-]+/[0-9]+(\.[0-9]+)*/[A-Za-z0-9_+.-]+\.deb$ ]]
}

ninjaone_url_version() {
  local rest="${1%/*}"
  echo "${rest##*/}"
}

ninjaone_url_host() {
  local rest="${1#https://}"
  echo "${rest%%/*}"
}

ninjaone_pkg_installed() {
  native_package_installed "$NINJAONE_PKG"
}

ninjaone_binary_present() {
  [[ -x "$NINJAONE_BIN" ]]
}

# Version the agent reports on disk (it self-updates, so this can be ahead of pacman's).
ninjaone_disk_version() {
  local v
  v="$(sudo sed -n 's/^Version=[[:space:]]*//p' "$NINJAONE_AGENT_CONF" 2>/dev/null | tr -d '[:space:]')"
  if [[ -z "$v" ]]; then
    case "$WORKSTATION_DISTRO" in
      arch) v="$(pacman -Q "$NINJAONE_PKG" 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]*$//')" ;;
      ubuntu) v="$(dpkg-query -W -f='${Version}' "$NINJAONE_PKG" 2>/dev/null)" ;;
    esac
  fi
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] || v=""
  echo "$v"
}

# True when $1 is strictly newer than $2.
ninjaone_version_gt() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ && "$2" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -Vu | wc -l)" -eq 2 && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# Supplied facts: a saved URL alone never grants ownership of a native agent.
ninjaone_ownership() {
  local distro="$1" package="$2" recorded="$3" present="$4"
  case "$distro" in
    arch) [[ "$package" == ninjaone-agent ]] && { echo owned; return; } ;;
    ubuntu) [[ -n "$package" && "$package" == "$recorded" ]] && { echo owned; return; } ;;
    *) return 1 ;;
  esac
  if [[ -n "$package" || "$present" == true ]]; then echo managed; else echo absent; fi
}

ninjaone_native_package_valid() {
  [[ "$1" =~ ^(ninjarmm-agent|ninjaone-agent)(-[a-z0-9][a-z0-9+.-]*)?$ ]]
}

# Resolve the native package from its actual file record, never a guessed tenant name.
ninjaone_install_owner() {
  local recorded="" package="" present=false path owner enrollment
  if [[ "$WORKSTATION_DISTRO" == arch ]]; then
    ninjaone_pkg_installed && package="$NINJAONE_PKG"
  else
    if [[ -f "$NINJAONE_OWNER_FILE" && ! -L "$NINJAONE_OWNER_FILE" && ! -L "${NINJAONE_OWNER_FILE%/*}" &&
          "$(stat -c '%u %a' "$NINJAONE_OWNER_FILE")" == '0 644' ]]; then
      read -r recorded enrollment <"$NINJAONE_OWNER_FILE" || recorded=""
      ninjaone_native_package_valid "$recorded" && [[ "$enrollment" =~ ^[a-f0-9]{64}$ ]] || recorded=""
    fi
    for path in "$NINJAONE_BIN" "$NINJAONE_AGENT_CONF"; do
      owner="$(dpkg-query -S "$path" 2>/dev/null)" || continue
      owner="${owner%%: /*}"
      ninjaone_native_package_valid "$owner" || { echo "managed $NINJAONE_PKG"; return; }
      [[ -z "$package" || "$package" == "$owner" ]] || { echo "managed $NINJAONE_PKG"; return; }
      package="$owner"
    done
    # The marker also identifies a broken/missing install for recovery.
    [[ -n "$package" ]] || package="$recorded"
    [[ -z "$package" ]] || NINJAONE_PKG="$package"
  fi
  if [[ -e /opt/NinjaRMMAgent ]] || systemctl cat ninjarmm-agent.service &>/dev/null; then present=true; fi
  printf '%s %s\n' "$(ninjaone_ownership "$WORKSTATION_DISTRO" "$package" "$recorded" "$present")" "$NINJAONE_PKG"
}

# A one-way digest pins host + enrollment UID without saving that credential as root.
ninjaone_enrollment_id() {
  ninjaone_url_valid "$1" || return 1
  printf '%s' "${1%/*/*}" | sha256sum | cut -d ' ' -f1
}

ninjaone_enrollment_matches() {
  local package expected
  ninjaone_url_valid "$1" || return 1
  read -r package expected <"$NINJAONE_OWNER_FILE" || return 1
  [[ "$(ninjaone_enrollment_id "$1")" == "$expected" ]]
}

ninjaone_archive_path_valid() {
  [[ "$1" != *..* && "$1" != *$'\n'* && "$1" != *$'\r'* ]] || return 1
  case "$1" in
    ./|./opt/|./tmp/|./opt/NinjaRMMAgent/|./opt/NinjaRMMAgent/*|./tmp/ninja-startup/|./tmp/ninja-startup/*|./tmp/ninja-uninstall/|./tmp/ninja-uninstall/*) return 0 ;;
    *) return 1 ;;
  esac
}

# No redirects: enrollment credentials must stay on the pinned HTTPS host.
# Archive pipelines finish before validation, so corrupt/empty lists fail closed.
ninjaone_fetch_and_check() {
  local url="$1" deb="$2" version entry listing types
  ninjaone_url_valid "$url" || return 1
  printf 'url = "%s"\n' "$url" | curl -q --config - -fsS --proto '=https' --max-time 600 -o "$deb" 2>/dev/null || {
    print_error_message "Download failed from $(ninjaone_url_host "$url") (get a fresh URL from the console)" >&2
    return 1
  }
  version="$(bsdtar -xOf "$deb" 'control.tar*' 2>/dev/null | bsdtar -xOf - ./control 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p')" || return 1
  if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ || "$version" != "$(ninjaone_url_version "$url")" ]]; then
    print_error_message "Invalid DEB version or installer/version mismatch" >&2
    return 1
  fi
  listing="$(bsdtar -xOf "$deb" 'data.tar*' 2>/dev/null | bsdtar -tf - 2>/dev/null)" || return 1
  [[ -n "$listing" ]] || return 1
  while IFS= read -r entry; do
    ninjaone_archive_path_valid "$entry" || {
      print_error_message "Unexpected path in agent DEB (contents withheld)" >&2
      return 1
    }
  done <<<"$listing"
  # Reject links/devices: an allowed path must not escape through a link target.
  types="$(bsdtar -xOf "$deb" 'data.tar*' 2>/dev/null | bsdtar -tvf - 2>/dev/null)" || return 1
  while IFS= read -r entry; do
    [[ "$entry" == -* || "$entry" == d* ]] || return 1
    [[ "$entry" != *' link to '* ]] || return 1
  done <<<"$types"
  echo "$version"
}

# Download, verify, repackage, and pacman -U the agent from $1. Never prints the URL.
ninjaone_build_and_install() {
  local url="$1" work version pkgfile package architecture owner

  if ! ninjaone_url_valid "$url"; then
    print_error_message "URL must be https://<region>.ninjarmm.com/agent/installer/<uid>/<version>/<name>.deb"
    return 1
  fi

  sudo -v || {
    print_error_message "sudo needs a terminal; run this from a real shell, not a non-interactive one"
    return 1
  }
  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    read -r owner NINJAONE_PKG < <(ninjaone_install_owner)
    [[ ! -L "${NINJAONE_OWNER_FILE%/*}" && ! -L "$NINJAONE_OWNER_FILE" ]] || {
      print_error_message "Native agent ownership state is redirected; retained"; return 1;
    }
    [[ "$owner" != managed ]] || { print_error_message "IT-managed NinjaOne retained; request changes from its owner"; return 1; }
    if [[ "$owner" == owned ]] && ! ninjaone_enrollment_matches "$url"; then
      print_error_message "Different or unknown enrollment; native agent retained"; return 1
    fi
    ensure_native_pkgs libarchive-tools || return 1
  else
    ensure_pacman_pkgs base-devel fakeroot libarchive || return 1
  fi

  work="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN
  mkdir "$work/dl" "$work/build" || return 1

  print_action_message "Downloading NinjaOne agent from $(ninjaone_url_host "$url")"
  version="$(ninjaone_fetch_and_check "$url" "$work/dl/agent.deb")" || return 1

  if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then
    package="$(dpkg-deb -f "$work/dl/agent.deb" Package 2>/dev/null)" || return 1
    architecture="$(dpkg-deb -f "$work/dl/agent.deb" Architecture 2>/dev/null)" || return 1
    ninjaone_native_package_valid "$package" && [[ "$architecture" == amd64 ]] || {
      print_error_message "Unexpected native agent package identity or architecture"; return 1;
    }
    if [[ "$owner" == owned && "$package" != "$NINJAONE_PKG" ]]; then
      print_error_message "Installer belongs to another enrollment; existing agent retained"; return 1
    fi
    if [[ "$owner" == absent ]] && dpkg-query -W -f='${Status}' "$package" &>/dev/null; then
      print_error_message "Native package record already exists without our ownership marker; retained"; return 1
    fi
    print_action_message "Installing native NinjaOne DEB $version (vendor enrollment output withheld)"
    # Vendor maintainer scripts may print enrollment data. No persistent install log.
    sudo apt-get install --yes --no-remove "$work/dl/agent.deb" >/dev/null 2>&1 || {
      print_error_message "Native NinjaOne install failed; inspect package health locally without sharing enrollment data"; return 1;
    }
    native_package_installed "$package" && dpkg-query -L "$package" | grep -Fx "$NINJAONE_BIN" >/dev/null || return 1
    printf '%s %s\n' "$package" "$(ninjaone_enrollment_id "$url")" >"$work/owner"
    sudo install -d -m 755 "${NINJAONE_OWNER_FILE%/*}" || return 1
    sudo install -m 644 -o root -g root "$work/owner" "$NINJAONE_OWNER_FILE" || return 1
    NINJAONE_PKG="$package"
    return 0
  fi

  cp "$NINJAONE_PKG_DIR/PKGBUILD" "$NINJAONE_PKG_DIR/ninjaone-agent.install" "$work/build/" || return 1
  print_action_message "Building $NINJAONE_PKG $version"
  (
    cd "$work/build"
    NINJAONE_DEB="$work/dl/agent.deb" NINJAONE_VERSION="$version" PKGDEST="$work/build" \
      makepkg -f --noconfirm --skipinteg
  ) || return 1

  pkgfile="$(find "$work/build" -maxdepth 1 -name "$NINJAONE_PKG-*.pkg.tar.*" -print -quit)"
  [[ -n "$pkgfile" ]] || {
    print_error_message "makepkg produced no package"
    return 1
  }

  print_action_message "Installing $NINJAONE_PKG $version"
  sudo pacman -U --noconfirm "$pkgfile"
}
