#!/bin/bash
# Migration: v2 -> v3 (dfa-morning renamed to dfa-daily, dfa-weekly added).
#
# The v3 rewrite renamed dfa-morning to dfa-daily and added a new dfa-weekly
# command that layers heavier, less-frequent maintenance (a forced package
# update, orphan cleanup) on top of dfa-daily. scripts/link-dotfiles.sh only
# creates symlinks for files currently in the repo; it never prunes ones
# whose source got renamed away. So a machine set up before this rename is
# left with a dangling ~/.local/bin/dfa-morning symlink pointing at a file
# that no longer exists, and neither the new dfa-daily nor dfa-weekly symlink
# yet.
#
# Run this once on any such existing machine to clean that up: it removes
# the dangling dfa-morning symlink (only if it's genuinely dangling —
# anything that still resolves, or isn't a symlink, is left alone) and
# relinks dotfiles to create dfa-daily and dfa-weekly. Safe to re-run.
#
# Usage: bash migrations/v2-to-v3-migration.sh

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
  dfa-morning
)

print_line_break "v2 -> v3 migration: dfa-morning -> dfa-daily rename cleanup"

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

print_info_message "Relinking dotfiles to create dfa-daily and dfa-weekly..."
bash "$REPO_ROOT/scripts/link-dotfiles.sh"

print_line_break "Migration complete"
print_info_message "Run 'source ~/.bashrc' (or open a new terminal) to pick up the updated aliases."
