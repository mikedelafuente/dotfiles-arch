#!/usr/bin/env bash
# --------------------------
# Common Header for Workstation Setup Scripts
# --------------------------
# This file sets up common variables and sources the function library
# It should be sourced at the beginning of each setup script

set -euo pipefail

# Resolve real user home when run under sudo
_user="${SUDO_USER:-$(whoami)}"
USER_HOME_DIR="$(eval echo "~${_user}")"
export USER_HOME_DIR

# Use parameter expansion to avoid "unbound variable" with set -u
if [ -z "${DF_SCRIPT_DIR:-}" ]; then
    DF_SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
fi

# Source common library functions
if [ -r "$DF_SCRIPT_DIR/fn-lib.sh" ]; then
  # shellcheck source=/dev/null
  source "$DF_SCRIPT_DIR/fn-lib.sh"
else
  echo "Missing required library: $DF_SCRIPT_DIR/fn-lib.sh"
  echo "DF_SCRIPT_DIR is $DF_SCRIPT_DIR"
  echo "Current user: $(whoami)"
  echo "Real user: ${_user}"
  exit 1
fi

# Reject unsupported hosts and Arch-only entrypoints before any writes.
# Re-detect on every invocation; an inherited/saved value cannot select the distro.
WORKSTATION_DISTRO="$(detect_workstation_distro)" || exit 1
require_workstation_entrypoint "$WORKSTATION_DISTRO" "${BASH_SOURCE[1]:-unknown}" || exit 1
WORKSTATION_ENTRYPOINT="${BASH_SOURCE[1]:-unknown}"
case "${WORKSTATION_ENTRYPOINT##*/}" in
  bootstrap.sh|sync.sh|run-profile-setup.sh|setup-gnome.sh|post-link-hooks.sh)
    GNOME_INSTALLED=false
    native_package_installed gnome-shell && GNOME_INSTALLED=true
    require_workstation_desktop "$WORKSTATION_DISTRO" "$GNOME_INSTALLED" || exit 1 ;;
esac

# Child setup processes must see newly installed user CLIs in this same run.
# Shell startup files are linked later; never append PATH changes to them.
export PATH="$USER_HOME_DIR/.local/bin:${CARGO_HOME:-$USER_HOME_DIR/.cargo}/bin:$PATH"
