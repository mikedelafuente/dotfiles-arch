#!/bin/bash

# -------------------------
# Link Dotfiles Script for Arch Linux
# This script creates symbolic links from the dotfiles repository to your home directory
# -------------------------

# -------------------------
# Allow for the profile name to be passed as an argument
# -------------------------
PROFILE_NAME="${1:-dela}"

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

print_tool_setup_start "Linking dotfiles"

# --------------------------
# Link Home Directory Dotfiles
# --------------------------

# Create symbolic links for dotfiles in the home directory
DOTFILES_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home"
DOTFILES_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"

print_info_message "Linking home directory dotfiles..."

for file in .bashrc .inputrc .profile .gitconfig .gitignore_global .nvim-cheatsheet.md .welcome.md .tmux.conf; do
  target="$USER_HOME_DIR/$file"
  source_file="$DOTFILES_HOME_DIR/$file"
  
  # Check if target exists and handle accordingly
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    print_warning_message "Warning: $target exists and is not a symlink."
    print_action_message "Backing up existing $target to $target.backup"
    mv "$target" "$target.backup"
  elif [ -L "$target" ]; then
    print_info_message "Overwriting existing symlink $target"
  fi
  ln -sf "$source_file" "$target"
  print_info_message "Linked: $file"
done

# --------------------------
# Link .local/bin Directory Files
# --------------------------

# Create symbolic links for scripts in the .local/bin directory
DOTFILES_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home/.local/bin"
BIN_TARGET_DIR="$USER_HOME_DIR/.local/bin"

if [ -d "$DOTFILES_BIN_DIR" ]; then
  mkdir -p "$BIN_TARGET_DIR"
  print_info_message "Linking .local/bin directory files..."

  find "$DOTFILES_BIN_DIR" -type f | while read -r file; do
    filename="$(basename "$file")"
    target="$BIN_TARGET_DIR/$filename"
    source_file="$file"

    # Check if target exists and handle accordingly
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      print_warning_message "Warning: $target exists and is not a symlink."
      print_action_message "Backing up existing $target to $target.backup"
      mv "$target" "$target.backup"
    elif [ -L "$target" ]; then
      print_info_message "Overwriting existing symlink $target"
    fi

    ln -sf "$source_file" "$target"
    chmod +x "$target"  # Ensure the script is executable
    print_info_message "Linked: .local/bin/$filename"
  done
fi

# --------------------------
# Link .config Directory Files
# --------------------------

# Iterate over all files in the .config directory recursively and create symlinks
# Create directories as needed
CONFIG_SOURCE_DIR="$DOTFILES_CONFIG_DIR"
CONFIG_TARGET_DIR="$USER_HOME_DIR/.config"
mkdir -p "$CONFIG_TARGET_DIR"

print_info_message "Linking .config directory files..."

find "$CONFIG_SOURCE_DIR" -type f | while read -r file; do
  relative_path="${file#$CONFIG_SOURCE_DIR/}"
  target="$CONFIG_TARGET_DIR/$relative_path"
  source_file="$file"
  target_dir="$(dirname "$target")"
  
  mkdir -p "$target_dir"
  
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    print_warning_message "Warning: $target exists and is not a symlink."
    print_action_message "Backing up existing $target to $target.backup"
    mv "$target" "$target.backup"
  elif [ -L "$target" ]; then
    print_info_message "Overwriting existing symlink $target"
  fi
  
  ln -sf "$source_file" "$target"
  print_info_message "Linked: .config/$relative_path"
done

print_tool_setup_complete "Linking dotfiles"
