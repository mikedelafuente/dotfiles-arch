#!/bin/bash

# -------------------------
# Link shared dotfiles for Arch / Ubuntu 26.04
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

# Linking is profile-agnostic; accept single or multi (comma/space) for log only.
PROFILE_NAME="$PROFILE_ARG"
if NORMALIZED="$(normalize_setup_profiles "$PROFILE_ARG" 2>/dev/null)"; then
  PROFILE_NAME="$(format_setup_profiles "$NORMALIZED")"
elif NORMALIZED="$(normalize_setup_profile "$PROFILE_ARG" 2>/dev/null)"; then
  PROFILE_NAME="$NORMALIZED"
else
  print_warning_message "Invalid profile arg '$PROFILE_ARG' — linking is profile-agnostic; continuing"
  PROFILE_NAME="work"
fi

print_tool_setup_start "Linking dotfiles"
print_info_message "Linking dotfiles for profiles: $PROFILE_NAME"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_HOME_DIR="$REPO_ROOT/home"
DOTFILES_CONFIG_DIR="$REPO_ROOT/config"

LINK_STATUS=0
LINK_LIST="$(mktemp)" || exit 1
trap 'rm -f "$LINK_LIST"' EXIT

# Preserve user files and foreign links. Existing identical repo targets are
# already linked; every other conflict fails instead of replacing a backup.
link_path() {
  local source_file="$1" target="$2"
  if [[ ! -e "$source_file" ]]; then
    print_error_message "Required link source is missing: $source_file"
    return 1
  fi
  if [[ -e "$target" && "$source_file" -ef "$target" ]]; then
    return 0
  fi
  link_core_cli_config "$source_file" "$target" || return $?
  print_info_message "Linked: $target"
}

# --------------------------
# Link Home Directory Dotfiles
# --------------------------

print_info_message "Linking home directory dotfiles..."

# ~/.gitconfig is machine-local, not linked; shared git settings are
# config/git/config (linked below with the rest of config/).
ensure_local_gitconfig || LINK_STATUS=1

for file in .bashrc .inputrc .profile .gitignore_global .nvim-cheatsheet.md .welcome.md .packages.md .tmux.conf; do
  link_path "$DOTFILES_HOME_DIR/$file" "$USER_HOME_DIR/$file" || LINK_STATUS=1
done

# --------------------------
# Link .local/bin Directory Files
# --------------------------

DOTFILES_BIN_DIR="$DOTFILES_HOME_DIR/.local/bin"
BIN_TARGET_DIR="$USER_HOME_DIR/.local/bin"

if [ -d "$DOTFILES_BIN_DIR" ]; then
  print_info_message "Linking .local/bin directory files..."

  find "$DOTFILES_BIN_DIR" -type f -print0 >"$LINK_LIST" || LINK_STATUS=1
  while IFS= read -r -d '' file; do
    filename="$(basename "$file")"
    link_path "$file" "$BIN_TARGET_DIR/$filename" || LINK_STATUS=1
  done <"$LINK_LIST"
else
  print_error_message "Required helper source directory is missing: $DOTFILES_BIN_DIR"
  LINK_STATUS=1
fi

# --------------------------
# Link .config Directory Files
# --------------------------

CONFIG_SOURCE_DIR="$DOTFILES_CONFIG_DIR"
CONFIG_TARGET_DIR="$USER_HOME_DIR/.config"
[[ -d "$CONFIG_SOURCE_DIR" ]] || { print_error_message "Required config source directory is missing"; exit 1; }

print_info_message "Linking .config directory files..."

find "$CONFIG_SOURCE_DIR" -type f -print0 >"$LINK_LIST" || LINK_STATUS=1
while IFS= read -r -d '' file; do
  relative_path="${file#"$CONFIG_SOURCE_DIR"/}"
  link_path "$file" "$CONFIG_TARGET_DIR/$relative_path" || LINK_STATUS=1
done <"$LINK_LIST"

# --------------------------
# Link Pi (coding agent) config files into ~/.pi/agent
# --------------------------
# Shared files under pi/ are version-controlled. Extensions under pi/extensions/
# are synced by sync-extensions.sh so configured extra repositories can contribute too.
# Machine-local files like auth.json and models-store.json are intentionally left untouched.

PI_SOURCE_DIR="$REPO_ROOT/pi"
PI_TARGET_DIR="$USER_HOME_DIR/.pi/agent"

if [ -d "$PI_SOURCE_DIR" ]; then
  print_info_message "Linking pi config files..."

  # Pi updates models-store.json with provider-check timestamps. Detach an old
  # repo symlink once, preserving its current contents as the local copy.
  PI_MODELS_STORE_SOURCE="$PI_SOURCE_DIR/models-store.json"
  PI_MODELS_STORE_TARGET="$PI_TARGET_DIR/models-store.json"
  if [ -L "$PI_MODELS_STORE_TARGET" ] \
    && [ "$(readlink -f "$PI_MODELS_STORE_TARGET")" = "$(readlink -f "$PI_MODELS_STORE_SOURCE")" ]; then
    if core_cli_parent_links_allowed "$PI_MODELS_STORE_TARGET"; then
      PI_MODELS_TMP="$(mktemp "$PI_MODELS_STORE_TARGET.XXXXXX")" || exit 1
      if cp -L "$PI_MODELS_STORE_TARGET" "$PI_MODELS_TMP" \
        && mv "$PI_MODELS_TMP" "$PI_MODELS_STORE_TARGET"; then
        print_info_message "Detached machine-local: .pi/agent/models-store.json"
      else
        rm -f "$PI_MODELS_TMP"
        LINK_STATUS=1
      fi
    else
      print_error_message "Pi models-store directory link conflict; preserved"
      LINK_STATUS=1
    fi
  fi

  find "$PI_SOURCE_DIR" -type f \
    ! -path "$PI_SOURCE_DIR/extensions/*" \
    ! -path "$PI_SOURCE_DIR/models-store.json" -print0 >"$LINK_LIST" || LINK_STATUS=1
  while IFS= read -r -d '' file; do
    relative_path="${file#"$PI_SOURCE_DIR"/}"
    link_path "$file" "$PI_TARGET_DIR/$relative_path" || LINK_STATUS=1
  done <"$LINK_LIST"
else
  print_error_message "Required Pi source directory is missing: $PI_SOURCE_DIR"
  LINK_STATUS=1
fi

if [[ "$LINK_STATUS" -ne 0 ]]; then
  print_error_message "Dotfile linking finished with conflicts/failures; user files preserved"
  exit 1
fi
print_tool_setup_complete "Linking dotfiles"
