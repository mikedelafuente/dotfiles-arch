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

print_tool_setup_start "Python"
ensure_language_runtime python python3 || exit 1
# Respect externally managed system Python; project packages belong in a venv.
python3 -I -c 'import pip, venv, ensurepip, pynvim' || {
    print_error_message 'Python requires pip, venv/ensurepip, and pynvim from native packages'
    exit 1
}
language_native_file_owned "$(type -P pip3 || true)" || {
    print_error_message 'pip3 command is missing or has a conflicting source'; exit 1;
}
print_info_message 'Project packages: python3 -m venv .venv; .venv/bin/python -m pip install <package>'
print_tool_setup_complete "Python"
