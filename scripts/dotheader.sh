#!/usr/bin/env bash
# --------------------------
# Common Header for Arch Setup Scripts
# --------------------------
# This file sets up common variables and sources the function library
# It should be sourced at the beginning of each setup script

set -euo pipefail

# Set a USER_HOME_DIR variable and export it for use in other scripts
export USER_HOME_DIR="$(eval echo ~${SUDO_USER:-$(whoami)})"

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
  echo "Real user: ${SUDO_USER:-$(whoami)}" 
  exit 1
fi
