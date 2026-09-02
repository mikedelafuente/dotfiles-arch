#!/bin/bash
# --------------------------
# Sync personal Cursor + Claude rules
# --------------------------
# For each source registered via dfa-sync-sources (plus dotfiles-arch itself),
# builds a normalized rules-build/<slug>/ staging dir (build_sync_source_rules
# in sync-sources-lib.sh): ready-made *.mdc rules are copied as-is, plain *.md
# rules with YAML frontmatter are auto-converted, and a per-source Claude file
# is generated from the bodies of just the alwaysApply:true rules. Standard-type
# sources contribute their rules/ subfolder; rules-root sources contribute
# their own folder directly (see dfa-sync-sources --type).
#
# From that staging dir: symlinks each *.mdc into ~/.cursor/rules/<name>.mdc,
# and (when a source produced one) symlinks its Claude file to
# ~/.claude/dfa-rules-<slug>.md with a matching @import line appended once to
# ~/.claude/CLAUDE.md. Any pre-existing real (non-symlinked) file at a target
# name — e.g. a leftover copy from another tool's installer — is deleted and
# replaced by the symlink. Prunes managed symlinks/import lines when a source
# is removed, unlisted, or no longer produces that output. Only ever touches
# entries whose target is a configured source's effective dir — real files
# elsewhere are left alone. Safe to re-run.

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
  build_sync_source_rules "${SYNC_SOURCE_REPOS_ALL[$i]}" "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
done

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

print_line_break "Syncing Claude rule imports"
for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
  sync_claude_rule_import "${SYNC_SOURCE_REPOS_ALL[$i]}" "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
done
prune_claude_rule_imports

print_success_message "Rules synced: $SYNC_RULES_LINKED_COUNT linked, $SYNC_RULES_PRUNED_COUNT pruned"
