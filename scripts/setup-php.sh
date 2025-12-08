#!/bin/bash

# --------------------------
# Setup PHP for Arch Linux
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

print_tool_setup_start "PHP"

# --------------------------
# Install PHP
# --------------------------

# Check if PHP is already installed
if command -v php &> /dev/null; then
    print_info_message "PHP is already installed. Skipping installation."
else
    print_info_message "Installing PHP and common extensions"
    sudo pacman -S --needed --noconfirm php php-gd php-intl php-sqlite php-pgsql

    # Verify installation
    if command -v php &> /dev/null; then
        print_info_message "PHP installed successfully."
    else
        print_error_message "PHP installation failed."
        exit 1
    fi
fi

# Print PHP version
print_info_message "PHP version: $(php --version | head -n 1)"

# --------------------------
# Install Composer
# --------------------------

if command -v composer &> /dev/null; then
    print_info_message "Composer is already installed. Skipping installation."
    print_info_message "Composer version: $(composer --version)"
else
    print_info_message "Installing Composer"
    sudo pacman -S --needed --noconfirm composer

    if command -v composer &> /dev/null; then
        print_info_message "Composer installed successfully."
        print_info_message "Composer version: $(composer --version)"
    else
        print_warning_message "Composer installation failed."
    fi
fi

# --------------------------
# Configure /etc/php/php.ini
# --------------------------

print_info_message "Configuring PHP extensions in /etc/php/php.ini"

PHP_INI="/etc/php/php.ini"
if [ -f "$PHP_INI" ]; then
    # Extensions to enable
    EXTENSIONS=(
        "curl"
        "iconv"
        "mysqli"
        "pdo_mysql"
        "pdo_sqlite"
        "sqlite3"
    )

    for ext in "${EXTENSIONS[@]}"; do
        # Uncomment the extension line
        sudo sed -i "/^;extension=${ext}/s/^;//" "$PHP_INI" || true
    done
    print_success_message "PHP extensions configured"
else
    print_warning_message "PHP configuration file not found: $PHP_INI"
fi

# --------------------------
# Install Laravel Installer
# --------------------------

if command -v laravel &> /dev/null; then
    print_info_message "Laravel installer is already installed."
    print_info_message "Laravel version: $(laravel --version)"
else
    if command -v composer &> /dev/null; then
        print_info_message "Installing Laravel installer globally via Composer"
        composer global require laravel/installer

        # Add Composer global bin to PATH if not already there
        COMPOSER_BIN="$USER_HOME_DIR/.config/composer/vendor/bin"
        if [[ ":$PATH:" != *":$COMPOSER_BIN:"* ]]; then
            print_info_message "Adding Composer global bin to PATH"
            echo "export PATH=\"\$PATH:$COMPOSER_BIN\"" >> "$USER_HOME_DIR/.bashrc"
        fi

        print_info_message "Laravel installer installed. Restart your terminal or run:"
        print_info_message "  export PATH=\"\$PATH:$COMPOSER_BIN\""
    else
        print_warning_message "Cannot install Laravel installer - Composer not available"
    fi
fi

print_tool_setup_complete "PHP"


