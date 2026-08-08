#!/bin/bash

# -------------------------
# Link Dotfiles Script for Arch Linux
# This script creates symbolic links from the dotfiles repository to your home directory
# -------------------------

# -------------------------
# Allow for the profile name to be passed as an argument
# -------------------------
PROFILE_NAME="${1:-work}"

# --------------------------
# Import Common Header
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

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
print_info_message "Linking dotfiles for profile: $PROFILE_NAME"

# --------------------------
# Link Home Directory Dotfiles
# --------------------------

DOTFILES_HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home"
DOTFILES_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"

print_info_message "Linking home directory dotfiles..."

for file in .bashrc .inputrc .profile .gitconfig .gitignore_global .nvim-cheatsheet.md .welcome.md; do
  target="$USER_HOME_DIR/$file"
  source_file="$DOTFILES_HOME_DIR/$file"

  if [ ! -e "$source_file" ]; then
    print_warning_message "Missing source $source_file — skipping"
    continue
  fi

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

DOTFILES_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home/.local/bin"
BIN_TARGET_DIR="$USER_HOME_DIR/.local/bin"

if [ -d "$DOTFILES_BIN_DIR" ]; then
  mkdir -p "$BIN_TARGET_DIR" 2>/dev/null \
    || sudo mkdir -p "$BIN_TARGET_DIR"
  print_info_message "Linking .local/bin directory files..."

  # Earlier bootstrap/setup under sudo can leave ~/.local/bin root-owned.
  if [ ! -w "$BIN_TARGET_DIR" ]; then
    print_warning_message "$BIN_TARGET_DIR is not writable — linking with sudo"
    print_info_message "Tip: sudo chown -R \"${SUDO_USER:-$(whoami)}\":\"${SUDO_USER:-$(whoami)}\" \"$BIN_TARGET_DIR\""
  fi

  while IFS= read -r -d '' file; do
    filename="$(basename "$file")"
    target="$BIN_TARGET_DIR/$filename"
    source_file="$file"

    if [ ! -e "$source_file" ]; then
      print_warning_message "Missing source $source_file — skipping"
      continue
    fi

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      print_warning_message "Warning: $target exists and is not a symlink."
      print_action_message "Backing up existing $target to $target.backup"
      mv "$target" "$target.backup" 2>/dev/null \
        || sudo mv "$target" "$target.backup"
    elif [ -L "$target" ]; then
      print_info_message "Overwriting existing symlink $target"
    fi

    ln -sfn "$source_file" "$target" 2>/dev/null \
      || sudo ln -sfn "$source_file" "$target"
    chmod +x "$target" 2>/dev/null \
      || sudo chmod +x "$target"
    print_info_message "Linked: .local/bin/$filename"
  done < <(find "$DOTFILES_BIN_DIR" -type f -print0)
fi

# --------------------------
# Link .config Directory Files
# --------------------------

CONFIG_SOURCE_DIR="$DOTFILES_CONFIG_DIR"
CONFIG_TARGET_DIR="$USER_HOME_DIR/.config"
mkdir -p "$CONFIG_TARGET_DIR"

print_info_message "Linking .config directory files..."

while IFS= read -r -d '' file; do
  relative_path="${file#"$CONFIG_SOURCE_DIR"/}"
  target="$CONFIG_TARGET_DIR/$relative_path"
  source_file="$file"
  target_dir="$(dirname "$target")"

  if [ ! -e "$source_file" ]; then
    print_warning_message "Missing source $source_file — skipping"
    continue
  fi

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
done < <(find "$CONFIG_SOURCE_DIR" -type f -print0)

print_tool_setup_complete "Linking dotfiles"
