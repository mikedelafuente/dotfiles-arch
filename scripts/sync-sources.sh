#!/bin/bash
# --------------------------
# Manage extra rules/skills source repos
# --------------------------
# dotfiles-arch is always the primary source; this command lists, adds, or
# removes additional sources synced by dfa-sync-rules and dfa-sync-skills.
# Each source has a type:
#   standard    (default) — the path has rules/ and/or skills/ subdirs, same
#               layout as dotfiles-arch itself.
#   skills-root — the path itself IS a flat folder of skill dirs (no skills/
#               subdir). Useful for a subfolder of someone else's skills repo,
#               e.g. ~/repos/mattpocock/skills/skills/engineering.
#   rules-root  — the path itself IS a flat folder of *.mdc files (no rules/
#               subdir).

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

SYNC_SOURCES_HINT="Run dfa-sync-skills && dfa-sync-rules to apply changes."

cmd_list() {
  local i path type
  print_line_break "Sync sources"
  print_info_message "Primary (always, standard): $REPO_ROOT"
  _read_sync_source_repo_lines
  if [[ ${#SYNC_SOURCE_REPO_LINES[@]} -eq 0 ]]; then
    print_info_message "Extra sources: (none — use: dfa-sync-sources add /path/to/repo)"
    return 0
  fi
  print_info_message "Extra sources:"
  for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
    path="${SYNC_SOURCE_REPO_LINES[$i]}"
    type="${SYNC_SOURCE_REPO_LINE_TYPES[$i]}"
    if [[ -d "$path" ]]; then
      print_info_message "  • [$type] $path"
    else
      print_warning_message "  • [$type] $path (missing)"
    fi
  done
}

cmd_add() {
  local raw="${1:-}"
  shift || true
  local type="standard"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)
        type="${2:-}"
        shift 2
        ;;
      --type=*)
        type="${1#--type=}"
        shift
        ;;
      *)
        print_error_message "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$raw" ]]; then
    print_error_message "Usage: dfa-sync-sources add /path/to/repo [--type standard|skills-root|rules-root]"
    exit 1
  fi
  if ! add_sync_source_repo "$raw" "$type"; then
    exit 1
  fi
  print_info_message "$SYNC_SOURCES_HINT"
}

cmd_remove() {
  local raw="${1:-}"
  shift || true
  local type=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)
        type="${2:-}"
        shift 2
        ;;
      --type=*)
        type="${1#--type=}"
        shift
        ;;
      *)
        print_error_message "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
  if [[ -z "$raw" ]]; then
    print_error_message "Usage: dfa-sync-sources remove /path/to/repo [--type standard|skills-root|rules-root]"
    exit 1
  fi
  if [[ -n "$type" ]] && ! is_valid_sync_source_type "$type"; then
    print_error_message "Unknown source type: $type (expected: ${SYNC_SOURCE_KNOWN_TYPES[*]})"
    exit 1
  fi

  local normalized
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    print_error_message "Invalid path: $raw"
    exit 1
  fi

  # Snapshot which type-entries actually match before removal, so we can prune
  # each one's symlinks precisely (a path could in principle be listed under
  # more than one type).
  _read_sync_source_repo_lines
  local removed_types=() i
  for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
    if [[ "${SYNC_SOURCE_REPO_LINES[$i]}" == "$normalized" ]] \
      && { [[ -z "$type" ]] || [[ "${SYNC_SOURCE_REPO_LINE_TYPES[$i]}" == "$type" ]]; }; then
      removed_types+=("${SYNC_SOURCE_REPO_LINE_TYPES[$i]}")
    fi
  done

  if remove_sync_source_repo "$raw" "$type"; then
    local t
    for t in "${removed_types[@]}"; do
      prune_sync_source_repo_symlinks "$normalized" "$t" \
        "$CURSOR_RULES_DIR" "$CLAUDE_SKILLS_DIR" "$CURSOR_SKILLS_DIR"
    done
    print_info_message "$SYNC_SOURCES_HINT"
  else
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: dfa-sync-sources list
       dfa-sync-sources add /path/to/repo [--type standard|skills-root|rules-root]
       dfa-sync-sources remove /path/to/repo [--type standard|skills-root|rules-root]

dotfiles-arch is always synced first; extra sources override on name collision.

Types:
  standard    (default) path has rules/ and/or skills/ subdirs
  skills-root path itself is a flat folder of skill dirs
  rules-root  path itself is a flat folder of *.mdc files

Examples:
  dfa-sync-sources add ~/repos/someone/rules-and-skills-repo
  dfa-sync-sources add ~/repos/mattpocock/skills/skills/engineering --type skills-root
  dfa-sync-sources remove ~/repos/mattpocock/skills/skills/engineering --type skills-root
EOF
}

case "${1:-}" in
  list | ls | "")
    cmd_list
    ;;
  add)
    shift
    cmd_add "$@"
    ;;
  remove | rm)
    shift
    cmd_remove "$@"
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
