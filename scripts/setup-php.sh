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

print_tool_setup_start "PHP"
[[ -z "${PHPRC:-}" && -z "${PHP_INI_SCAN_DIR:-}" ]] || {
    print_error_message 'Custom PHP configuration environment; resolve before setup (retained)'
    exit 1
}
ensure_language_runtime php php composer || exit 1
PHP_VERSION="$(language_installed_version php)" || exit 1
PHP_PATHS="$(php_configuration_paths "$WORKSTATION_DISTRO" "$PHP_VERSION")" || exit 1
read -r PHP_INI PHP_SCAN_DIR <<<"$PHP_PATHS"
LOADED_INI="$(php -r 'echo php_ini_loaded_file();')" || exit 1
[[ "$LOADED_INI" == "$PHP_INI" && -f "$PHP_INI" && ! -L "$PHP_INI" ]] || {
    print_error_message "PHP config conflict: expected $PHP_INI; existing config retained"
    exit 1
}
MODULES="$(php -m)" || exit 1
# Enable missing shared extensions only, matching exact names (not pdo_mysql_extra).
for extension in curl iconv mysqli pdo_mysql pdo_sqlite sqlite3 gd intl pgsql pdo_pgsql mbstring dom xml; do
    grep -Fxiq "$extension" <<<"$MODULES" && continue
    case "$WORKSTATION_DISTRO" in
        arch)
            grep -Eq "^[;[:space:]]*extension=${extension}(\.so)?[[:space:]]*$" "$PHP_INI" || {
                print_error_message "Missing PHP extension directive: $extension"; exit 1;
            }
            sudo sed -i -E "/^[[:space:]]*;[[:space:]]*extension=${extension}(\.so)?[[:space:]]*$/s/;[[:space:]]*//" "$PHP_INI" || exit 1 ;;
        ubuntu)
            [[ -f "/etc/php/${PHP_VERSION%.*}/mods-available/$extension.ini" ]] || {
                print_error_message "Missing PHP module config: $extension"; exit 1;
            }
            sudo /usr/sbin/phpenmod -v "${PHP_VERSION%.*}" -s cli "$extension" || exit 1 ;;
    esac
done
MODULES="$(php -m)" || exit 1
php_modules_allowed "$MODULES" || exit 1
print_info_message "PHP CLI configuration: $PHP_INI; extensions: $PHP_SCAN_DIR"
COMPOSER_HOME_DIR="$(composer config --global home)" || exit 1
language_user_path_allowed "$USER_HOME_DIR" "$COMPOSER_HOME_DIR" || exit 1
if [[ -f "$COMPOSER_HOME_DIR/composer.json" ]]; then
    COMPOSER_BIN_DIR="$(composer global config bin-dir --absolute)" || exit 1
else
    COMPOSER_BIN_DIR="$(composer global config --global bin-dir --absolute)" || exit 1
fi
language_user_path_allowed "$USER_HOME_DIR" "$COMPOSER_BIN_DIR" || exit 1
LARAVEL_COMMAND="$(type -P laravel || true)"
[[ -z "$LARAVEL_COMMAND" || "$LARAVEL_COMMAND" == "$COMPOSER_BIN_DIR/laravel" ]] || {
    print_error_message 'Laravel launcher conflicts with Composer global bin-dir; retained'; exit 1;
}
if ! composer global show laravel/installer --format=json >/dev/null 2>&1; then
    composer global require laravel/installer || exit 1
fi
[[ -x "$COMPOSER_BIN_DIR/laravel" ]] || { print_error_message 'Laravel command missing after Composer install'; exit 1; }
"$COMPOSER_BIN_DIR/laravel" --version || exit 1
print_info_message "Laravel commands: $COMPOSER_BIN_DIR; custom bin-dir must be on your PATH"
print_info_message 'Laravel updates: composer global update laravel/installer'
print_tool_setup_complete "PHP"
