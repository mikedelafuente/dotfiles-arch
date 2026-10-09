#!/bin/bash

# --------------------------
# Import Common Header 
# --------------------------

# add header file
CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# source header (uses SCRIPT_DIR and loads lib.sh)
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# --------------------------
# End Import Common Header 
# --------------------------

print_tool_setup_start "Go"
ensure_language_runtime go go gopls || exit 1
# A version string alone does not prove that the installed compiler has its stdlib.
GO_ROOT="$(go env GOROOT)" || exit 1
[[ -d "$GO_ROOT/src" && -d "$GO_ROOT/pkg/tool" ]] || {
    print_error_message 'Go installation lacks its standard library or compiler tools'
    exit 1
}
print_tool_setup_complete "Go"
