#!/bin/bash
# --------------------------
# Sync personal Cursor rules
# --------------------------
# Symlinks each *.mdc rule file from dotfiles-arch and any extra repos
# registered via dfa-sync-sources into ~/.cursor/rules/<name>.mdc, and prunes managed
# symlinks when the source is removed or the repo is unlisted. Standard-type
# sources contribute their rules/ subfolder; rules-root sources contribute their
# own folder directly (see dfa-sync-sources --type). Only ever touches symlinks
# whose target is a configured source's effective rules dir — real files
# elsewhere are left alone. Cursor only — Claude Code has no equivalent
# auto-loaded rules directory. Safe to re-run.

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
TARGET_DIR="$USER_HOME_DIR/.cursor/rules"

print_line_break "Syncing rules"

collect_sync_source_repos "$REPO_ROOT"
if [[ ${#SYNC_SOURCE_REPOS_ALL[@]} -eq 0 ]]; then
  print_warning_message "No rule sources configured — nothing to sync"
  exit 0
fi

mkdir -p "$TARGET_DIR"

SYNC_RULES_LINKED_COUNT=0
SYNC_RULES_PRUNED_COUNT=0
declare -A _sync_rules_linked_names=()

for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
  repo_root="${SYNC_SOURCE_REPOS_ALL[$i]}"
  source_type="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
  if ! { rules_dir="$(sync_source_effective_dir "$repo_root" "$source_type" rules)" && [[ -d "$rules_dir" ]]; }; then
    print_info_message "No rules under $repo_root ($source_type) — skipping"
    continue
  fi
  sync_rules_from_repo "$repo_root" "$source_type" "$TARGET_DIR"
done

prune_managed_symlinks "$TARGET_DIR" rules

print_success_message "Rules synced: $SYNC_RULES_LINKED_COUNT linked, $SYNC_RULES_PRUNED_COUNT pruned"
