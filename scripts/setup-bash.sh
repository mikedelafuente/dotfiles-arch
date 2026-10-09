#!/bin/bash

# --------------------------
# Setup Bash Shell for rolling Arch / Ubuntu 26.04
# --------------------------

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

print_tool_setup_start "Bash"

REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
SHELL_FILES=(.bashrc .inputrc .profile .welcome.md .packages.md .nvim-cheatsheet.md)
for file in "${SHELL_FILES[@]}"; do
    core_cli_link_allowed "$REPO_ROOT/home/$file" "$USER_HOME_DIR/$file" || {
        print_error_message "Shell config conflict: $USER_HOME_DIR/$file; preserved"
        exit 1
    }
done
core_cli_link_allowed "$REPO_ROOT/config/starship.toml" "$USER_HOME_DIR/.config/starship.toml" || {
    print_error_message "Starship config conflict; preserved"
    exit 1
}

# --------------------------
# Install Bash
# --------------------------

ensure_core_cli bash
ensure_core_cli bash-completion

for file in "${SHELL_FILES[@]}"; do
    link_core_cli_config "$REPO_ROOT/home/$file" "$USER_HOME_DIR/$file"
done
link_core_cli_config "$REPO_ROOT/config/starship.toml" "$USER_HOME_DIR/.config/starship.toml"

# --------------------------
# Set Bash as Default Shell
# --------------------------

# Set Bash as the default shell
if [ "${SHELL:-}" != /bin/bash ] && [ "${SHELL:-}" != /usr/bin/bash ]; then
    current_shell=/bin/bash
    print_info_message "Changing default shell ($SHELL) to bash ($current_shell)"
    chsh -s "$current_shell"
else
    print_info_message "Bash is already the default shell. Skipping change."
fi

print_tool_setup_complete "Bash"
