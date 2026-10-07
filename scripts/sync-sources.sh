#!/bin/bash
# --------------------------
# Manage extra rules/skills/extensions source repos
# --------------------------
# dotfiles-arch is always the primary source; this command lists, adds, or
# removes additional sources synced by dfa-sync-rules, dfa-sync-skills, and
# dfa-sync-extensions. Each source has a type:
#   standard    (default) — the path has rules/, skills/, and/or extensions/ subdirs
#               (dotfiles-arch uses pi/extensions/ for Pi extensions), same layout
#               as dotfiles-arch itself.
#   skills-root — the path itself IS a folder of nested skill dirs (no skills/
#               subdir). Useful for a subfolder of someone else's skills repo,
#               e.g. ~/repos/mattpocock/skills/skills/engineering.
#   rules-root  — the path itself IS a flat folder of *.mdc files (no rules/
#               subdir).
#   extensions-root — the path itself IS a flat folder of Pi extensions (no
#               extensions/ subdir).

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
PI_SKILLS_DIR="$(pi_agent_dir)/skills"
CODEX_SKILLS_DIR="$(codex_home_dir)/skills"

SYNC_SOURCES_HINT="Run dfa-sync-extensions && dfa-sync-skills && dfa-sync-rules to apply changes."

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
    print_error_message "Usage: dfa-sync-sources add /path/to/repo [--type standard|skills-root|rules-root|extensions-root]"
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
    print_error_message "Usage: dfa-sync-sources remove /path/to/repo [--type standard|skills-root|rules-root|extensions-root]"
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
        "$CURSOR_RULES_DIR" "$CLAUDE_SKILLS_DIR" "$CURSOR_SKILLS_DIR" "$PI_SKILLS_DIR" "$CODEX_SKILLS_DIR"
    done
    refresh_pi_agent_rules "$REPO_ROOT"
    print_info_message "$SYNC_SOURCES_HINT"
  else
    exit 1
  fi
}

# Redraw the reorder TUI: current _REORDER_PATHS/_REORDER_TYPES order with
# _REORDER_CURSOR highlighted. Bottom of the list = highest priority, since
# sync_rules_from_repo apply sources in file order and
# later sources override earlier ones on a name collision.
_reorder_draw() {
  clear
  print_line_break "Reorder sync sources"
  print_info_message "Primary (always synced first, lowest priority, standard): $REPO_ROOT"
  echo
  print_info_message "Rules/extensions: later entries override earlier ones. Duplicate skill names fail sync."
  echo
  local i
  for i in "${!_REORDER_PATHS[@]}"; do
    if [[ "$i" -eq "$_REORDER_CURSOR" ]]; then
      printf '\e[7m > [%s] %s\e[0m\n' "${_REORDER_TYPES[$i]}" "${_REORDER_PATHS[$i]}"
    else
      printf '   [%s] %s\n' "${_REORDER_TYPES[$i]}" "${_REORDER_PATHS[$i]}"
    fi
  done
  echo
  print_info_message "↑/k ↓/j move cursor   K/J move entry up/down   Enter/w save   q cancel"
}

# Swap two entries in the working _REORDER_PATHS/_REORDER_TYPES arrays.
_reorder_swap() {
  local a="$1" b="$2" tmp_p tmp_t
  tmp_p="${_REORDER_PATHS[$a]}"
  tmp_t="${_REORDER_TYPES[$a]}"
  _REORDER_PATHS[a]="${_REORDER_PATHS[$b]}"
  _REORDER_TYPES[a]="${_REORDER_TYPES[$b]}"
  _REORDER_PATHS[b]="$tmp_p"
  _REORDER_TYPES[b]="$tmp_t"
}

cmd_reorder() {
  _read_sync_source_repo_lines
  local n=${#SYNC_SOURCE_REPO_LINES[@]}
  if [[ "$n" -eq 0 ]]; then
    print_info_message "No extra sources to reorder — use: dfa-sync-sources add /path/to/repo"
    return 0
  fi
  if [[ "$n" -eq 1 ]]; then
    print_info_message "Only one extra source — nothing to reorder."
    return 0
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    print_error_message "reorder requires an interactive terminal"
    return 1
  fi

  _REORDER_PATHS=("${SYNC_SOURCE_REPO_LINES[@]}")
  _REORDER_TYPES=("${SYNC_SOURCE_REPO_LINE_TYPES[@]}")
  _REORDER_CURSOR=0

  local key esc
  while true; do
    _reorder_draw
    IFS= read -rsn1 key
    if [[ "$key" == $'\x1b' ]]; then
      read -rsn2 -t 0.01 esc 2>/dev/null || esc=""
      case "$esc" in
        '[A') key='k' ;;
        '[B') key='j' ;;
        *) key='' ;;
      esac
    fi
    case "$key" in
      k)
        ((_REORDER_CURSOR > 0)) && _REORDER_CURSOR=$((_REORDER_CURSOR - 1))
        ;;
      j)
        ((_REORDER_CURSOR < n - 1)) && _REORDER_CURSOR=$((_REORDER_CURSOR + 1))
        ;;
      K)
        if ((_REORDER_CURSOR > 0)); then
          _reorder_swap "$_REORDER_CURSOR" "$((_REORDER_CURSOR - 1))"
          _REORDER_CURSOR=$((_REORDER_CURSOR - 1))
        fi
        ;;
      J)
        if ((_REORDER_CURSOR < n - 1)); then
          _reorder_swap "$_REORDER_CURSOR" "$((_REORDER_CURSOR + 1))"
          _REORDER_CURSOR=$((_REORDER_CURSOR + 1))
        fi
        ;;
      w | "")
        # shellcheck disable=SC2034 # consumed by write_sync_source_repos (sync-sources-lib.sh)
        SYNC_SOURCE_REPOS=("${_REORDER_PATHS[@]}")
        # shellcheck disable=SC2034 # consumed by write_sync_source_repos (sync-sources-lib.sh)
        SYNC_SOURCE_REPO_TYPES=("${_REORDER_TYPES[@]}")
        write_sync_source_repos
        clear
        print_success_message "Saved new priority order."
        cmd_list
        print_info_message "$SYNC_SOURCES_HINT"
        return 0
        ;;
      q)
        clear
        print_info_message "Cancelled — no changes made."
        return 0
        ;;
    esac
  done
}

cmd_manage() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    print_error_message "manage requires an interactive terminal; use list/add/remove instead"
    return 1
  fi

  local action raw choice type i step failed
  while true; do
    cmd_list
    cat <<'EOF'

  1) Add a source directory
  2) Remove a source (keeps its files on disk)
  3) Reorder source priority
  4) Apply changes: sync skills, rules, and extensions
  q) Done
EOF
    read -rp 'Choose [1-4, Enter to exit]: ' action || return 0
    case "$action" in
      1)
        print_info_message "Use a local clone or directory; clone remote repos first."
        read -rp 'Source path (blank cancels): ' raw || return 0
        [[ -n "$raw" ]] || continue
        # read does not expand a typed ~/ path; expand only that prefix,
        # never evaluate shell input.
        # shellcheck disable=SC2088 # literal tilde prefix entered at the prompt
        case "$raw" in
          '~') raw="$USER_HOME_DIR" ;;
          '~/'*) raw="$USER_HOME_DIR/${raw:2}" ;;
        esac
        cat <<'EOF'
  1) standard — repo with skills/, rules/, or extensions/ subfolders
  2) skills-root — directory containing skill folders recursively
  3) rules-root — directory containing rule files directly
  4) extensions-root — directory containing Pi extensions directly
EOF
        read -rp 'Source type [1, blank defaults to standard; q cancels]: ' choice || return 0
        case "$choice" in
          1|'') type=standard ;;
          2) type=skills-root ;;
          3) type=rules-root ;;
          4) type=extensions-root ;;
          q) continue ;;
          *) print_warning_message "Choose a source type from 1 to 4."; continue ;;
        esac
        cmd_add "$raw" --type "$type"
        ;;
      2)
        _read_sync_source_repo_lines
        if [[ ${#SYNC_SOURCE_REPO_LINES[@]} -eq 0 ]]; then
          print_info_message "No extra sources to remove."
          continue
        fi
        for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
          printf '  %d) [%s] %s\n' "$((i + 1))" "${SYNC_SOURCE_REPO_LINE_TYPES[$i]}" "${SYNC_SOURCE_REPO_LINES[$i]}"
        done
        read -rp 'Remove source number (blank cancels): ' choice || return 0
        [[ -n "$choice" ]] || continue
        # Compare strings instead of evaluating user input as arithmetic.
        raw=""
        for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
          if [[ "$choice" == "$((i + 1))" ]]; then
            raw="${SYNC_SOURCE_REPO_LINES[$i]}"
            type="${SYNC_SOURCE_REPO_LINE_TYPES[$i]}"
            break
          fi
        done
        if [[ -z "$raw" ]]; then
          print_warning_message "Choose one of the listed source numbers."
          continue
        fi
        cmd_remove "$raw" --type "$type"
        ;;
      3) cmd_reorder ;;
      4)
        failed=0
        for step in sync-skills sync-rules sync-extensions; do
          if ! bash "$DF_SCRIPT_DIR/$step.sh"; then
            print_error_message "Failed: $step"
            failed=1
          fi
        done
        [[ "$failed" -eq 0 ]] || return 1
        print_success_message "Sources applied."
        ;;
      q|'') return 0 ;;
      *) print_warning_message "Choose 1-4, or Enter to exit." ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: dfa-sync-sources [manage]
       dfa-sync-sources list
       dfa-sync-sources add /path/to/repo [--type standard|skills-root|rules-root|extensions-root]
       dfa-sync-sources remove /path/to/repo [--type standard|skills-root|rules-root|extensions-root]
       dfa-sync-sources reorder

With no arguments, opens the source manager in a terminal (lists sources when
non-interactive). Add/remove local directories, reorder priority, or apply changes.
Removing a source keeps the source files on disk.

dotfiles-arch is always synced first; extra sources override on name collision.
Use 'reorder' to change extra sources' relative priority (bottom of the list
wins on a name collision).

Types:
  standard    (default) path has rules/, skills/, and/or extensions/ subdirs
               (dotfiles-arch uses pi/extensions/ for Pi extensions)
  skills-root path itself is a folder of nested skill dirs
  rules-root  path itself is a flat folder of *.mdc files
  extensions-root path itself is a flat folder of Pi extensions

Examples:
  dfa-sync-sources add ~/repos/someone/rules-and-skills-repo
  dfa-sync-sources add ~/repos/mattpocock/skills/skills/engineering --type skills-root
  dfa-sync-sources remove ~/repos/mattpocock/skills/skills/engineering --type skills-root
  dfa-sync-sources reorder
EOF
}

case "${1:-}" in
  "")
    if [[ -t 0 && -t 1 ]]; then cmd_manage; else cmd_list; fi
    ;;
  manage)
    cmd_manage
    ;;
  list | ls)
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
  reorder | order | rank)
    cmd_reorder
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
