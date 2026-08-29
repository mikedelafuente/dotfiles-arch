#!/bin/bash
# Migration: v1 -> v2 (day-to-day command rename cleanup).
#
# The v2 rewrite renamed ten day-to-day commands under a dfa- prefix
# (morning -> dfa-morning, sync-dotfiles -> dfa-sync-dotfiles, etc. — see
# CLAUDE.md). scripts/link-dotfiles.sh only creates symlinks for files
# currently in the repo; it never prunes ones whose source got renamed
# away. So a machine set up before the rename is left with ten dangling
# ~/.local/bin symlinks pointing at files that no longer exist, and none of
# the new dfa-* symlinks yet.
#
# Run this once on any such existing machine to clean that up: it removes
# the dangling old-named symlinks (only if they're genuinely dangling —
# anything that still resolves, or isn't a symlink, is left alone) and
# relinks dotfiles to create the new dfa-* commands. Safe to re-run.
#
# Usage: bash migrations/v1-to-v2-migration.sh

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

# The ten day-to-day commands renamed with a dfa- prefix (see CLAUDE.md).
OLD_NAMES=(
  morning
  sync-dotfiles
  repos
  update-repos
  update-system
  check-dotfiles
  remove-orphans
  sync-skills
  sync-rules
  sync-sources
)

print_line_break "v1 -> v2 migration: dfa- command rename cleanup"

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

print_info_message "Relinking dotfiles to create the new dfa-* commands..."
bash "$REPO_ROOT/scripts/link-dotfiles.sh"

print_line_break "Migration complete"
print_info_message "Run 'source ~/.bashrc' (or open a new terminal) to pick up the updated aliases."
