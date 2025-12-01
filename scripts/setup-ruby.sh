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
# Install Ruby
# --------------------------

# Check if Ruby is already installed
if command -v ruby &> /dev/null; then
    print_info_message "Ruby is already installed: $(ruby --version)"
else
    print_info_message "Installing Ruby from official Arch repositories"
    sudo pacman -S --needed --noconfirm ruby
    print_info_message "Ruby installed: $(ruby --version)"
fi

# --------------------------
# Setup Ruby Gem PATH Early
# --------------------------

# Get Ruby version and setup gem bin directory path BEFORE checking for gems
RUBY_VERSION=$(ruby -e 'puts RbConfig::CONFIG["ruby_version"]' 2>/dev/null)
GEM_BIN_DIR="$USER_HOME_DIR/.local/share/gem/ruby/$RUBY_VERSION/bin"

# Add gem bin directory to PATH for this session if it exists
if [ -d "$GEM_BIN_DIR" ]; then
    if ! echo "$PATH" | grep -q "$GEM_BIN_DIR"; then
        print_info_message "Adding gem bin directory to PATH: $GEM_BIN_DIR"
        export PATH="$GEM_BIN_DIR:$PATH"
    fi
fi

# --------------------------
# Install Bundler
# --------------------------

# Check if bundler is already installed (check both command and gem list)
if gem list -i '^bundler$' &> /dev/null; then
    print_info_message "Bundler is already installed: $(bundle --version 2>/dev/null || echo 'installed')"
else
    print_info_message "Installing Bundler gem to user directory"
    gem install --user-install bundler --no-document
    print_success_message "Bundler installed successfully"
fi

# --------------------------
# Install Rails Dependencies
# --------------------------

print_info_message "Installing Rails dependencies"

# Node.js (JavaScript runtime for Rails asset pipeline)
if command -v node &> /dev/null; then
    print_info_message "Node.js is already installed: $(node --version)"
else
    print_info_message "Installing Node.js"
    sudo pacman -S --needed --noconfirm nodejs npm
fi

# Additional build dependencies for native gems
if pacman -Q base-devel &> /dev/null; then
    print_info_message "Build dependencies already installed"
else
    print_info_message "Installing build dependencies for Ruby gems"
    sudo pacman -S --needed --noconfirm base-devel
fi

# SQLite (default Rails database for development)
if pacman -Q sqlite &> /dev/null; then
    print_info_message "SQLite is already installed"
else
    print_info_message "Installing SQLite"
    sudo pacman -S --needed --noconfirm sqlite
fi

# --------------------------
# Install Rails
# --------------------------

# Check if Rails is already installed (check both command and gem list)
if gem list -i '^rails$' &> /dev/null; then
    print_info_message "Rails is already installed: $(rails --version 2>/dev/null || echo 'installed')"
else
    print_info_message "Installing Rails gem to user directory (this may take a few minutes)"
    gem install --user-install rails --no-document
    print_success_message "Rails installed successfully"

    # Verify installation
    if command -v rails &> /dev/null; then
        print_info_message "Rails version: $(rails --version)"
    else
        print_warning_message "Rails installed but not in PATH. You may need to restart your shell."
    fi
fi

# --------------------------
# Configure PATH in Shell RC Files
# --------------------------

# Add to .bashrc if not already there
BASHRC="$USER_HOME_DIR/.bashrc"
if [ -f "$BASHRC" ]; then
    if ! grep -q "gem/ruby.*bin" "$BASHRC"; then
        print_info_message "Adding gem bin directory to ~/.bashrc"
        {
            echo ""
            echo "# Ruby gem binaries"
            echo "if [ -d \"\$HOME/.local/share/gem/ruby/$RUBY_VERSION/bin\" ]; then"
            echo "    export PATH=\"\$HOME/.local/share/gem/ruby/$RUBY_VERSION/bin:\$PATH\""
            echo "fi"
        } >> "$BASHRC"
    else
        print_info_message "Gem bin directory already configured in ~/.bashrc"
    fi
fi

print_tool_setup_complete "Ruby on Rails"
