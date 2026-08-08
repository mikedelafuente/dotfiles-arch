#!/bin/bash

# -------------------------
# Link Dotfiles Script for Arch Linux
# This script creates symbolic links from the dotfiles repository to your home directory
# -------------------------

PROFILE_ARG="${1:-work}"

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

if ! PROFILE_NAME="$(normalize_setup_profile "$PROFILE_ARG")"; then
  print_warning_message "Invalid profile arg '$PROFILE_ARG' — linking is profile-agnostic; continuing as work"
  PROFILE_NAME="work"
fi

print_tool_setup_start "Linking dotfiles"
print_info_message "Linking dotfiles for profile: $PROFILE_NAME"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_HOME_DIR="$REPO_ROOT/home"
DOTFILES_CONFIG_DIR="$REPO_ROOT/config"

# Link source → target with backup + sudo fallback for root-owned targets.
link_path() {
  local source_file="$1"
  local target="$2"
  local target_dir

  if [ ! -e "$source_file" ]; then
    print_warning_message "Missing source $source_file — skipping"
    return 0
  fi

  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir" 2>/dev/null \
    || sudo mkdir -p "$target_dir"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    print_warning_message "Warning: $target exists and is not a symlink."
    print_action_message "Backing up existing $target to $target.backup"
    mv "$target" "$target.backup" 2>/dev/null \
      || sudo mv "$target" "$target.backup"
  elif [ -L "$target" ]; then
    print_info_message "Overwriting existing symlink $target"
  fi

  if ! ln -sfn "$source_file" "$target" 2>/dev/null; then
    print_warning_message "Not writable — linking with sudo: $target"
    print_info_message "Tip: sudo chown -R \"${SUDO_USER:-$(whoami)}\":\"${SUDO_USER:-$(whoami)}\" \"$target_dir\""
    sudo ln -sfn "$source_file" "$target"
  fi
}

# --------------------------
# Link Home Directory Dotfiles
# --------------------------

print_info_message "Linking home directory dotfiles..."

for file in .bashrc .inputrc .profile .gitconfig .gitignore_global .nvim-cheatsheet.md .welcome.md; do
  link_path "$DOTFILES_HOME_DIR/$file" "$USER_HOME_DIR/$file"
  print_info_message "Linked: $file"
done

# --------------------------
# Link .local/bin Directory Files
# --------------------------

DOTFILES_BIN_DIR="$DOTFILES_HOME_DIR/.local/bin"
BIN_TARGET_DIR="$USER_HOME_DIR/.local/bin"

if [ -d "$DOTFILES_BIN_DIR" ]; then
  mkdir -p "$BIN_TARGET_DIR" 2>/dev/null \
    || sudo mkdir -p "$BIN_TARGET_DIR"
  print_info_message "Linking .local/bin directory files..."

  if [ ! -w "$BIN_TARGET_DIR" ]; then
    print_warning_message "$BIN_TARGET_DIR is not writable — linking with sudo"
    print_info_message "Tip: sudo chown -R \"${SUDO_USER:-$(whoami)}\":\"${SUDO_USER:-$(whoami)}\" \"$BIN_TARGET_DIR\""
  fi

  while IFS= read -r -d '' file; do
    filename="$(basename "$file")"
    link_path "$file" "$BIN_TARGET_DIR/$filename"
    # Do not chmod symlinks into the repo (avoids dirtying git file modes).
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
  link_path "$file" "$CONFIG_TARGET_DIR/$relative_path"
  print_info_message "Linked: .config/$relative_path"
done < <(find "$CONFIG_SOURCE_DIR" -type f -print0)

print_tool_setup_complete "Linking dotfiles"
