#!/bin/bash
# --------------------------
# Manage extra rules/skills source repos
# --------------------------
# dotfiles-arch is always the primary source; this command lists, adds, or
# removes additional repos whose top-level rules/ and skills/ dirs are synced
# by sync-rules and sync-skills.

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
CURSOR_RULES_DIR="$USER_HOME_DIR/.cursor/rules"
CLAUDE_SKILLS_DIR="$USER_HOME_DIR/.claude/skills"
CURSOR_SKILLS_DIR="$USER_HOME_DIR/.cursor/skills"

SYNC_SOURCES_HINT="Run sync-skills && sync-rules to apply changes."

cmd_list() {
  local path
  print_line_break "Sync sources"
  print_info_message "Primary (always): $REPO_ROOT"
  _read_sync_source_repo_lines
  if [[ ${#SYNC_SOURCE_REPO_LINES[@]} -eq 0 ]]; then
    print_info_message "Extra sources: (none — use: sync-sources add /path/to/repo)"
    return 0
  fi
  print_info_message "Extra sources:"
  for path in "${SYNC_SOURCE_REPO_LINES[@]}"; do
    if [[ -d "$path" ]]; then
      print_info_message "  • $path"
    else
      print_warning_message "  • $path (missing)"
    fi
  done
}

cmd_add() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    print_error_message "Usage: sync-sources add /path/to/repo"
    exit 1
  fi
  add_sync_source_repo "$raw"
  print_info_message "$SYNC_SOURCES_HINT"
}

cmd_remove() {
  local raw="${1:-}" normalized
  if [[ -z "$raw" ]]; then
    print_error_message "Usage: sync-sources remove /path/to/repo"
    exit 1
  fi
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    print_error_message "Invalid path: $raw"
    exit 1
  fi
  if remove_sync_source_repo "$raw"; then
    prune_sync_source_repo_symlinks "$normalized" \
      "$CURSOR_RULES_DIR" "$CLAUDE_SKILLS_DIR" "$CURSOR_SKILLS_DIR"
    print_info_message "$SYNC_SOURCES_HINT"
  else
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: sync-sources list
       sync-sources add /path/to/repo
       sync-sources remove /path/to/repo

dotfiles-arch is always synced first; extra repos override on name collision.
EOF
}

case "${1:-}" in
  list | ls | "")
    cmd_list
    ;;
  add)
    cmd_add "${2:-}"
    ;;
  remove | rm)
    cmd_remove "${2:-}"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    print_error_message "Unknown command: $1"
    usage
    exit 1
    ;;
esac
