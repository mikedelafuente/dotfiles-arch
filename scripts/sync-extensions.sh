#!/bin/bash
# --------------------------
# Sync Pi extensions from dotfiles-arch and configured extra sources
# --------------------------
# Standard sources contribute extensions/ (or pi/extensions/ for this repo);
# extensions-root sources contribute the source directory itself. Later sources
# override earlier entries.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# shellcheck source=/dev/null
source "$DF_SCRIPT_DIR/sync-sources-lib.sh"

REPO_ROOT="$(cd "$DF_SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$(pi_agent_dir)/extensions"

print_line_break "Syncing Pi extensions"

collect_sync_source_repos "$REPO_ROOT"
mkdir -p "$TARGET_DIR"

SYNC_EXTENSIONS_LINKED_COUNT=0
SYNC_EXTENSIONS_PRUNED_COUNT=0
declare -A _sync_extensions_linked_names=()

for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
  sync_extensions_from_repo \
    "${SYNC_SOURCE_REPOS_ALL[$i]}" \
    "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}" \
    "$TARGET_DIR"
done

prune_managed_extension_symlinks "$TARGET_DIR"

print_success_message "Pi extensions synced: $SYNC_EXTENSIONS_LINKED_COUNT linked, $SYNC_EXTENSIONS_PRUNED_COUNT pruned"
