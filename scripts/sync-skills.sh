#!/bin/bash
# --------------------------
# Sync personal Claude/Cursor skills
# --------------------------
# Symlinks each folder under skills/ into ~/.claude/skills/<name> and
# ~/.cursor/skills/<name>, and prunes any symlink we previously created
# there once its source folder is removed from the repo. Only ever touches
# symlinks that resolve back into this repo's skills/ dir — real
# directories/files (e.g. company-provided skills copied in separately)
# are always left alone. Safe to re-run.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

REPO_ROOT="$(cd "$DF_SCRIPT_DIR/.." && pwd)"
REPO_SKILLS_DIR="$REPO_ROOT/skills"
TARGET_DIRS=("$USER_HOME_DIR/.claude/skills" "$USER_HOME_DIR/.cursor/skills")

print_line_break "Syncing skills"

if [ ! -d "$REPO_SKILLS_DIR" ]; then
  print_warning_message "No $REPO_SKILLS_DIR — nothing to sync"
  exit 0
fi

LINKED_COUNT=0
PRUNED_COUNT=0

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"

  # Link: every direct subdirectory of skills/ becomes a symlink here.
  while IFS= read -r -d '' skill_dir; do
    skill_name="$(basename "$skill_dir")"
    if [ ! -f "$skill_dir/SKILL.md" ]; then
      print_warning_message "skills/$skill_name has no SKILL.md — linking anyway"
    fi
    ln -sfn "$skill_dir" "$target_dir/$skill_name"
    print_info_message "Linked: $target_dir/$skill_name"
    LINKED_COUNT=$((LINKED_COUNT + 1))
  done < <(find "$REPO_SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

  # Prune: symlinks in target_dir that point into our skills/ dir but whose
  # source no longer exists there.
  while IFS= read -r -d '' entry; do
    [ -L "$entry" ] || continue
    resolved="$(readlink -f "$entry" 2>/dev/null || true)"
    [[ "$resolved" == "$REPO_SKILLS_DIR"/* ]] || continue
    [ -e "$resolved" ] && continue
    print_action_message "Removing stale skill symlink: $entry"
    rm -f "$entry"
    PRUNED_COUNT=$((PRUNED_COUNT + 1))
  done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -print0)
done

print_success_message "Skills synced: $LINKED_COUNT linked, $PRUNED_COUNT pruned"
