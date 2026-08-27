#!/bin/bash
# --------------------------
# Sync personal Claude/Cursor skills
# --------------------------
# Symlinks each folder under skills/ from dotfiles-arch and any extra repos
# registered via sync-sources into ~/.claude/skills/<name> and
# ~/.cursor/skills/<name>, and prunes managed symlinks when the source is removed
# or the repo is unlisted. Only ever touches symlinks under {source}/skills/ for
# configured sources — real directories elsewhere are left alone. Safe to re-run.

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

for repo_root in "${SYNC_SOURCE_REPOS_ALL[@]}"; do
  if [[ ! -d "$repo_root/skills" ]]; then
    print_info_message "No skills/ in $repo_root — skipping"
  fi
done

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"
  declare -A _sync_skills_linked_names=()

  for repo_root in "${SYNC_SOURCE_REPOS_ALL[@]}"; do
    [[ -d "$repo_root/skills" ]] || continue
    sync_skills_from_repo "$repo_root" "$target_dir"
  done

  prune_managed_symlinks "$target_dir" skills
done

print_success_message "Skills synced: $SYNC_SKILLS_LINKED_COUNT linked, $SYNC_SKILLS_PRUNED_COUNT pruned"
