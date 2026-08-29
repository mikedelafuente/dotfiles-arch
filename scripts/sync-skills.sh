#!/bin/bash
# --------------------------
# Sync personal Claude/Cursor skills
# --------------------------
# Symlinks each skill folder from dotfiles-arch and any extra repos registered
# via dfa-sync-sources into ~/.claude/skills/<name> and ~/.cursor/skills/<name>, and
# prunes managed symlinks when the source is removed or the repo is unlisted.
# Standard-type sources contribute their skills/ subfolder; skills-root sources
# contribute their own folder directly (see dfa-sync-sources --type). Only ever
# touches symlinks whose target is a configured source's effective skills dir —
# real directories elsewhere are left alone. Safe to re-run.

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
TARGET_DIRS=("$USER_HOME_DIR/.claude/skills" "$USER_HOME_DIR/.cursor/skills")

print_line_break "Syncing skills"

collect_sync_source_repos "$REPO_ROOT"
if [[ ${#SYNC_SOURCE_REPOS_ALL[@]} -eq 0 ]]; then
  print_warning_message "No skill sources configured — nothing to sync"
  exit 0
fi

SYNC_SKILLS_LINKED_COUNT=0
SYNC_SKILLS_PRUNED_COUNT=0

for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
  repo_root="${SYNC_SOURCE_REPOS_ALL[$i]}"
  source_type="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
  if ! { skills_dir="$(sync_source_effective_dir "$repo_root" "$source_type" skills)" && [[ -d "$skills_dir" ]]; }; then
    print_info_message "No skills under $repo_root ($source_type) — skipping"
  fi
done

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"
  declare -A _sync_skills_linked_names=()

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    repo_root="${SYNC_SOURCE_REPOS_ALL[$i]}"
    source_type="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
    sync_skills_from_repo "$repo_root" "$source_type" "$target_dir"
  done

  prune_managed_symlinks "$target_dir" skills
done

print_success_message "Skills synced: $SYNC_SKILLS_LINKED_COUNT linked, $SYNC_SKILLS_PRUNED_COUNT pruned"
