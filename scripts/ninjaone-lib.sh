#!/usr/bin/env bash
# --------------------------
# ninjaone-lib.sh - helpers shared by setup-ninjaone.sh and update-ninjaone.sh
# --------------------------
# Source after dotheader.sh. The installer URL embeds the org's ClientUID, so it is
# a credential: it lives only in NINJAONE_ENV_FILE (mode 600, outside the repo) and
# is never printed — messages show the host and version only.

NINJAONE_PKG="ninjaone-agent"
NINJAONE_BIN="/opt/NinjaRMMAgent/programfiles/ninjarmm-linagent"
NINJAONE_AGENT_CONF="/opt/NinjaRMMAgent/programfiles/config/agent.conf"
NINJAONE_PKG_DIR="$DF_SCRIPT_DIR/ninjaone"

ninjaone_env_file() {
  echo "$(bootstrap_config_dir)/ninjaone.env"
}

# Loads NINJAONE_INSTALLER_URL from the env file unless the environment already sets it.
ninjaone_load_url() {
  local f saved_url="${NINJAONE_INSTALLER_URL:-}"
  f="$(ninjaone_env_file)"
  # shellcheck source=/dev/null
  [[ -r "$f" ]] && source "$f"
  [[ -n "$saved_url" ]] && NINJAONE_INSTALLER_URL="$saved_url"
  NINJAONE_INSTALLER_URL="${NINJAONE_INSTALLER_URL:-}"
}

ninjaone_save_url() {
  local url="$1" f
  f="$(ninjaone_env_file)"
  mkdir -p "$(dirname "$f")"
  (
    umask 077
    {
      echo "# NinjaOne installer URL (credential - never commit)"
      printf 'NINJAONE_INSTALLER_URL=%q\n' "$url"
      printf 'NINJAONE_INSTALLER_VERSION=%q\n' "$(ninjaone_url_version "$url")"
    } >"$f"
  )
  chmod 600 "$f"
}

# https://<region>.ninjarmm.com/agent/installer/<uid>/<version>/<name>.deb
ninjaone_url_valid() {
  [[ "$1" =~ ^https://[a-z0-9.-]+\.(ninjarmm|rmmservice)\.com/agent/installer/[^/]+/[0-9]+(\.[0-9]+)*/[^/]+\.deb$ ]]
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
  pacman -Q "$NINJAONE_PKG" &>/dev/null
}

ninjaone_binary_present() {
  [[ -x "$NINJAONE_BIN" ]]
}

# Version the agent reports on disk (it self-updates, so this can be ahead of pacman's).
ninjaone_disk_version() {
  local v
  v="$(sudo sed -n 's/^Version=[[:space:]]*//p' "$NINJAONE_AGENT_CONF" 2>/dev/null | tr -d '[:space:]')"
  [[ -n "$v" ]] || v="$(pacman -Q "$NINJAONE_PKG" 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]*$//')"
  echo "$v"
}

# True when $1 is strictly newer than $2.
ninjaone_version_gt() {
  [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

# Download $1 to $2, then check the archive layout. Prints the deb's Version on success.
ninjaone_fetch_and_check() {
  local url="$1" deb="$2" version entry
  curl -fsSL --proto '=https' --max-time 600 -o "$deb" "$url" || {
    print_error_message "Download failed from $(ninjaone_url_host "$url") (expired or wrong URL? get a fresh one from the NinjaOne console)"
    return 1
  }

  version="$(bsdtar -xOf "$deb" 'control.tar*' 2>/dev/null | bsdtar -xOf - ./control 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | tr -d '[:space:]')"
  if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    print_error_message "Not a NinjaOne agent .deb (unreadable or invalid Version field)"
    return 1
  fi

  while IFS= read -r entry; do
    case "$entry" in
      ./|./opt/|./tmp/|./opt/NinjaRMMAgent/*|./tmp/ninja-startup/*|./tmp/ninja-uninstall/*) ;;
      *)
        print_error_message "Unexpected path in .deb: $entry"
        return 1
        ;;
    esac
    [[ "$entry" == *..* ]] && {
      print_error_message "Unexpected path in .deb: $entry"
      return 1
    }
  done < <(bsdtar -xOf "$deb" 'data.tar*' | bsdtar -tf -)

  echo "$version"
}

# Download, verify, repackage, and pacman -U the agent from $1. Never prints the URL.
ninjaone_build_and_install() {
  local url="$1" work version pkgfile

  if ! ninjaone_url_valid "$url"; then
    print_error_message "URL must be https://<region>.ninjarmm.com/agent/installer/<uid>/<version>/<name>.deb"
    return 1
  fi

  sudo -v || {
    print_error_message "sudo needs a terminal; run this from a real shell, not a non-interactive one"
    return 1
  }
  ensure_pacman_pkgs base-devel fakeroot libarchive

  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" RETURN
  mkdir "$work/dl" "$work/build"

  print_action_message "Downloading NinjaOne agent from $(ninjaone_url_host "$url")"
  version="$(ninjaone_fetch_and_check "$url" "$work/dl/agent.deb")" || return 1

  cp "$NINJAONE_PKG_DIR/PKGBUILD" "$NINJAONE_PKG_DIR/ninjaone-agent.install" "$work/build/"
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
