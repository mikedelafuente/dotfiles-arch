#!/bin/bash

# --------------------------
# Setup pi (Pi coding agent) CLI for Arch and Ubuntu
# --------------------------
# Installs the stock published package. See pi-dev/README.md for the plan to
# switch this to a local/custom build.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "pi"

ensure_harness_cli pi || exit $?

print_tool_setup_complete "pi"
