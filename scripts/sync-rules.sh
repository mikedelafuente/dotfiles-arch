#!/bin/bash
# --------------------------
# Sync personal Cursor rules
# --------------------------
# Symlinks each *.mdc file under rules/ into ~/.cursor/rules/<name>.mdc, and
# prunes any symlink we previously created there once its source file is
# removed from the repo. Only ever touches symlinks that resolve back into
# this repo's rules/ dir — real files (e.g. rules placed there some other
# way) are always left alone. Cursor only — Claude Code has no equivalent
# auto-loaded rules directory. Safe to re-run.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

REPO_ROOT="$(cd "$DF_SCRIPT_DIR/.." && pwd)"
REPO_RULES_DIR="$REPO_ROOT/rules"
TARGET_DIR="$USER_HOME_DIR/.cursor/rules"

print_line_break "Syncing rules"

if [ ! -d "$REPO_RULES_DIR" ]; then
  print_warning_message "No $REPO_RULES_DIR — nothing to sync"
  exit 0
fi

mkdir -p "$TARGET_DIR"

LINKED_COUNT=0
PRUNED_COUNT=0

# Link: every *.mdc file directly under rules/ becomes a symlink here.
while IFS= read -r -d '' rule_file; do
  rule_name="$(basename "$rule_file")"
  if ! head -n1 "$rule_file" | grep -q '^---$'; then
    print_warning_message "rules/$rule_name has no YAML frontmatter — linking anyway"
  fi
  ln -sfn "$rule_file" "$TARGET_DIR/$rule_name"
  print_info_message "Linked: $TARGET_DIR/$rule_name"
  LINKED_COUNT=$((LINKED_COUNT + 1))
done < <(find "$REPO_RULES_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.mdc' -print0)

# Prune: symlinks in TARGET_DIR that point into our rules/ dir but whose
# source no longer exists there.
while IFS= read -r -d '' entry; do
  [ -L "$entry" ] || continue
  resolved="$(readlink -f "$entry" 2>/dev/null || true)"
  [[ "$resolved" == "$REPO_RULES_DIR"/* ]] || continue
  [ -e "$resolved" ] && continue
  print_action_message "Removing stale rule symlink: $entry"
  rm -f "$entry"
  PRUNED_COUNT=$((PRUNED_COUNT + 1))
done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -print0)

print_success_message "Rules synced: $LINKED_COUNT linked, $PRUNED_COUNT pruned"
