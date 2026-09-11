#!/bin/bash
# Migration: v3 -> v4 (the `code` launcher became `dev`, defaulting to Zed).
#
# v4 renamed home/.local/bin/code to home/.local/bin/dev and made Zed the
# default target, with the tmux + Neovim session behind `dev --tmux`.
# scripts/link-dotfiles.sh only creates symlinks for files currently in the
# repo; it never prunes ones whose source got renamed away. So a machine set
# up before this rename is left with a dangling ~/.local/bin/code symlink and
# no ~/.local/bin/dev yet.
#
# The stale `code` symlink is worse than cosmetic here. Claude Code's /ide
# command probes PATH for a VS Code CLI named `code`; it found this script,
# passed it --install-extension, and reported a successful install that never
# happened. Removing the symlink lets that probe fail honestly.
#
# Run this once on any such existing machine: it removes the dangling symlink
# (only if it's genuinely dangling — anything that still resolves, or isn't a
# symlink, is left alone) and relinks dotfiles to create `dev`. Safe to re-run.
#
# Usage: bash migrations/v3-to-v4-migration.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"

if [ -r "$REPO_ROOT/scripts/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/dotheader.sh"
else
  echo "Missing header file: $REPO_ROOT/scripts/dotheader.sh"
  exit 1
fi

BIN_DIR="$USER_HOME_DIR/.local/bin"

OLD_NAMES=(
  code
)

print_line_break "v3 -> v4 migration: code -> dev rename cleanup"

removed=0
for name in "${OLD_NAMES[@]}"; do
  target="$BIN_DIR/$name"
  if [ -L "$target" ] && [ ! -e "$target" ]; then
    print_info_message "Removing dangling symlink: $target"
    rm "$target"
    removed=$((removed + 1))
  elif [ -e "$target" ] || [ -L "$target" ]; then
    print_warning_message "Skipping $target — not a dangling symlink (still resolves, or isn't a symlink); leaving it alone"
  fi
  # else: nothing there — already migrated (or never existed) — skip silently
done

if ((removed == 0)); then
  print_info_message "No dangling pre-rename symlinks found."
else
  print_info_message "Removed $removed dangling symlink(s)."
fi

print_info_message "Relinking dotfiles to create dev..."
bash "$REPO_ROOT/scripts/link-dotfiles.sh"

print_info_message "Registering Zed as the default text and source-file handler..."
bash "$REPO_ROOT/scripts/setup-zed.sh"

print_line_break "Migration complete"
print_info_message "Run 'source ~/.bashrc' (or open a new terminal) to pick up the updated aliases."
