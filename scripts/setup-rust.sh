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

print_tool_setup_start "Rust and Cargo"
[[ "$EUID" != 0 ]] || { print_error_message 'Run Rust setup as the user, without sudo'; exit 1; }
# Keep existing homes/defaults; never replace a user's nightly or pinned toolchain.
export CARGO_HOME="${CARGO_HOME:-$USER_HOME_DIR/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$USER_HOME_DIR/.rustup}"
language_user_path_allowed "$USER_HOME_DIR" "$CARGO_HOME" || exit 1
language_user_path_allowed "$USER_HOME_DIR" "$RUSTUP_HOME" || exit 1
export PATH="$CARGO_HOME/bin:$PATH"
OWNER="$(language_rust_owner)" || { print_error_message 'Conflicting Rust proxies; retained'; exit 1; }
DEFAULT=''
RUST_VERSION=''
CARGO_VERSION=''
case "$OWNER" in
    native-rustup|user-rustup)
        if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
            DEFAULT="$RUSTUP_TOOLCHAIN"
            RUST_VERSION="$(language_installed_version rustc)" || exit 1
            CARGO_VERSION="$(language_installed_version cargo)" || exit 1
        elif DEFAULT="$(rustup default 2>&1)"; then
            RUST_VERSION="$(language_installed_version rustc)" || exit 1
            CARGO_VERSION="$(language_installed_version cargo)" || exit 1
        elif [[ "$DEFAULT" == *'no default toolchain configured'* ]]; then
            DEFAULT=''
        else
            print_error_message "Cannot read Rust default: $DEFAULT"
            exit 1
        fi ;;
    native)
        RUST_VERSION="$(language_installed_version rustc)" || exit 1
        CARGO_VERSION="$(language_installed_version cargo)" || exit 1 ;;
esac
ACTION="$(rust_toolchain_selection "$WORKSTATION_DISTRO" "$OWNER" "$DEFAULT" "$RUST_VERSION" "$CARGO_VERSION")" || exit 1
ensure_language_packages build || exit 1
if [[ "$OWNER" == none ]]; then
    MANAGER="$(rust_manager_selection "$WORKSTATION_DISTRO" "$OWNER")" || exit 1
    if [[ "$MANAGER" == user-rustup ]]; then
        install_user_rustup || exit 1
    else
        ensure_language_packages rust || exit 1
    fi
    hash -r
    OWNER="$(language_rust_owner)" || exit 1
    [[ "$OWNER" == "$MANAGER" ]] || { print_error_message 'Rustup installation incomplete'; exit 1; }
    if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]] || DEFAULT="$(rustup default 2>&1)"; then
        ACTION=retain
    elif [[ "$DEFAULT" != *'no default toolchain configured'* ]]; then
        print_error_message "Cannot read Rust default: $DEFAULT"
        exit 1
    fi
fi
if [[ "$ACTION" == initialize ]]; then
    rustup default stable || exit 1
fi
for command in rustc cargo; do
    VERSION="$(language_installed_version "$command")" || exit 1
    print_info_message "$command $VERSION"
done
if [[ "$OWNER" == native ]]; then
    print_info_message 'Existing distro Rust retained; update with dfa-update-system'
else
    print_info_message 'Default toolchain retained; update toolchains with rustup update'
    if [[ "$OWNER" == user-rustup ]]; then
        print_info_message 'User rustup binary: rustup self update'
    else
        print_info_message 'Distro rustup binary: dfa-update-system (do not self-update)'
    fi
fi
print_tool_setup_complete "Rust and Cargo"
