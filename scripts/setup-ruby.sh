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

# --------------------------
# Install Ruby on Rails
# --------------------------

# Check if Ruby is already installed
if command -v ruby &> /dev/null; then
    print_info_message "Ruby is already installed. Skipping installation."
else
    print_info_message "Installing Ruby from official Arch repositories"

    # Install Ruby
    sudo pacman -S --needed --noconfirm ruby
fi

# Print Ruby version
print_info_message "Ruby version: $(ruby --version)"

# Install bundler if not already installed
if command -v bundle &> /dev/null; then
    print_info_message "Bundler is already installed. Skipping installation."
else
    print_info_message "Installing Bundler gem"
    gem install bundler
fi

# Install Rails dependencies
print_info_message "Installing Rails dependencies"

# Node.js (JavaScript runtime for Rails asset pipeline)
if command -v node &> /dev/null; then
    print_info_message "Node.js is already installed. Skipping installation."
else
    print_info_message "Installing Node.js"
    sudo pacman -S --needed --noconfirm nodejs npm
fi

# Additional build dependencies for native gems
print_info_message "Installing build dependencies for Ruby gems"
sudo pacman -S --needed --noconfirm base-devel

# SQLite (default Rails database for development)
if pacman -Q sqlite &> /dev/null; then
    print_info_message "SQLite is already installed. Skipping installation."
else
    print_info_message "Installing SQLite"
    sudo pacman -S --needed --noconfirm sqlite
fi

# Install Rails if not already installed
if command -v rails &> /dev/null; then
    print_info_message "Rails is already installed."
    print_info_message "Rails version: $(rails --version)"
else
    print_info_message "Installing Rails gem"
    gem install rails
    print_success_message "Rails installed successfully"
    print_info_message "Rails version: $(rails --version)"
fi

print_tool_setup_complete "Ruby on Rails"


