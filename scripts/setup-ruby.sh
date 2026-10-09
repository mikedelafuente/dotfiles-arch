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

print_tool_setup_start "Ruby on Rails"
ensure_language_runtime ruby ruby || exit 1
# RubyGems selects the user path (XDG or legacy ~/.gem); never pin the ABI here.
GEM_USER_DIR="$(ruby -rrubygems -e 'print Gem.user_dir')" || exit 1
language_user_path_allowed "$USER_HOME_DIR" "$GEM_USER_DIR/bin" || exit 1
language_native_file_owned "$(readlink -f "$(type -P gem || true)")" || {
    print_error_message 'RubyGems launcher is missing or has a conflicting source'; exit 1;
}
# Custom GEM_HOME/GEM_PATH can silently select system or unrelated installations.
[[ -z "${GEM_HOME:-}" || "$GEM_HOME" == "$GEM_USER_DIR" ]] || {
    print_error_message 'GEM_HOME conflicts with user gems; retained'; exit 1;
}
[[ -z "${GEM_PATH:-}" ]] || { print_error_message 'Custom GEM_PATH; resolve gem ownership before setup'; exit 1; }
export PATH="$GEM_USER_DIR/bin:$PATH"
for library in openssl psych; do
    ruby -r "$library" -e '' || { print_error_message "Ruby requires $library"; exit 1; }
done
for tool in bundler rails; do
    ensure_user_gem "$tool" "$GEM_USER_DIR" || exit 1
done
load_nvm || true
command -v node &>/dev/null || {
    print_error_message 'Rails JavaScript runtime missing; run setup-node.sh (NVM)'
    exit 1
}
print_info_message "Gem commands: $GEM_USER_DIR/bin (loaded by ~/.bashrc)"
print_tool_setup_complete "Ruby on Rails"
