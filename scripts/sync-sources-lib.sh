#!/usr/bin/env bash
# Sync-sources domain: config CRUD (add/remove/list extra rules/skills source
# repos) plus the link/prune helpers used by sync-rules.sh and sync-skills.sh.
# Expects fn-lib.sh (print_*, bootstrap_config_dir) to be loaded.
#
# Each configured source has a type:
#   standard    — repo root has rules/ (*.mdc files) and/or skills/ (skill dirs)
#                 under it, same layout as dotfiles-arch itself.
#   skills-root — the path itself IS a flat folder of skill dirs (no skills/
#                 subdir). Useful for a subfolder of someone else's skills repo,
#                 e.g. mattpocock/skills/skills/engineering.
#   rules-root  — the path itself IS a flat folder of *.mdc files (no rules/
#                 subdir).
#
# Config file lines: bare "path" means standard (for backwards compatibility);
# "type:path" is explicit. Comments (#) and blank lines are ignored.

SYNC_SOURCE_KNOWN_TYPES=(standard skills-root rules-root)

# True when type is one of SYNC_SOURCE_KNOWN_TYPES.
is_valid_sync_source_type() {
  local type="${1:-}" t
  for t in "${SYNC_SOURCE_KNOWN_TYPES[@]}"; do
    [[ "$type" == "$t" ]] && return 0
  done
  return 1
}

sync_sources_config_file() {
  echo "$(bootstrap_config_dir)/sync-sources"
}

# Normalize a repo path for comparison (stdout). Returns 1 if empty.
normalize_sync_source_repo_path() {
  local path="${1:-}"
  [[ -n "$path" ]] || return 1
  realpath -m "$path"
}

# Parse one config line into _SYNC_SOURCE_LINE_TYPE / _SYNC_SOURCE_LINE_PATH.
# Bare paths default to type "standard". Returns 1 if the path half is empty.
_parse_sync_source_line() {
  local line="${1:-}" type path
  case "$line" in
    skills-root:*) type="skills-root" path="${line#skills-root:}" ;;
    rules-root:*)  type="rules-root"  path="${line#rules-root:}" ;;
    standard:*)    type="standard"    path="${line#standard:}" ;;
    *)             type="standard"    path="$line" ;;
  esac
  [[ -n "$path" ]] || return 1
  _SYNC_SOURCE_LINE_TYPE="$type"
  _SYNC_SOURCE_LINE_PATH="$path"
}

# Read every non-comment line from sync-sources into parallel arrays
# SYNC_SOURCE_REPO_LINES (normalized paths) / SYNC_SOURCE_REPO_LINE_TYPES,
# deduped by type+path, file order. Does not check that paths exist.
_read_sync_source_repo_lines() {
  SYNC_SOURCE_REPO_LINES=()
  SYNC_SOURCE_REPO_LINE_TYPES=()
  local f line normalized
  local -A seen=()
  f="$(sync_sources_config_file)"
  [[ -r "$f" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if ! _parse_sync_source_line "$line"; then
      continue
    fi
    if ! normalized="$(normalize_sync_source_repo_path "$_SYNC_SOURCE_LINE_PATH")"; then
      continue
    fi
    if [[ -n "${seen[${_SYNC_SOURCE_LINE_TYPE}:${normalized}]:-}" ]]; then
      continue
    fi
    seen["${_SYNC_SOURCE_LINE_TYPE}:${normalized}"]=1
    SYNC_SOURCE_REPO_LINES+=("$normalized")
    SYNC_SOURCE_REPO_LINE_TYPES+=("$_SYNC_SOURCE_LINE_TYPE")
  done <"$f"
}

# Load extra sync source repos into parallel arrays SYNC_SOURCE_REPOS /
# SYNC_SOURCE_REPO_TYPES (existing dirs only).
load_sync_source_repos() {
  SYNC_SOURCE_REPOS=()
  SYNC_SOURCE_REPO_TYPES=()
  local i path
  _read_sync_source_repo_lines
  for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
    path="${SYNC_SOURCE_REPO_LINES[$i]}"
    if [[ ! -d "$path" ]]; then
      print_warning_message "Sync source not found (skipping): $path"
      continue
    fi
    SYNC_SOURCE_REPOS+=("$path")
    SYNC_SOURCE_REPO_TYPES+=("${SYNC_SOURCE_REPO_LINE_TYPES[$i]}")
  done
}

# Write parallel SYNC_SOURCE_REPOS / SYNC_SOURCE_REPO_TYPES arrays to
# sync-sources config. Standard-type entries are written as bare paths
# (backwards compatible); other types get an explicit "type:" prefix.
write_sync_source_repos() {
  local dir f i path type
  dir="$(bootstrap_config_dir)"
  f="$(sync_sources_config_file)"
  mkdir -p "$dir"
  {
    echo "# Extra rules/skills source repos, one per line: path | type:path"
    echo "# Types: standard (default, has rules/ + skills/ subdirs), skills-root"
    echo "# (path is itself a flat folder of skill dirs), rules-root (path is"
    echo "# itself a flat folder of *.mdc files)."
    echo "# Managed by dfa-sync-sources add/remove — dotfiles-arch is always primary"
    for i in "${!SYNC_SOURCE_REPOS[@]}"; do
      path="${SYNC_SOURCE_REPOS[$i]}"
      type="${SYNC_SOURCE_REPO_TYPES[$i]}"
      if [[ "$type" == "standard" ]]; then
        printf '%s\n' "$path"
      else
        printf '%s:%s\n' "$type" "$path"
      fi
    done
  } >"$f"
  chmod 600 "$f" 2>/dev/null || true
}

# Append a repo to sync-sources if not already listed under that type.
# Returns 1 on error.
add_sync_source_repo() {
  local raw="${1:-}" type="${2:-standard}" normalized i
  [[ -n "$raw" ]] || return 1
  if ! is_valid_sync_source_type "$type"; then
    print_error_message "Unknown source type: $type (expected: ${SYNC_SOURCE_KNOWN_TYPES[*]})"
    return 1
  fi
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    return 1
  fi
  if [[ ! -d "$normalized" ]]; then
    print_error_message "Not a directory: $normalized"
    return 1
  fi
  SYNC_SOURCE_REPOS=()
  SYNC_SOURCE_REPO_TYPES=()
  _read_sync_source_repo_lines
  SYNC_SOURCE_REPOS=("${SYNC_SOURCE_REPO_LINES[@]}")
  SYNC_SOURCE_REPO_TYPES=("${SYNC_SOURCE_REPO_LINE_TYPES[@]}")
  for i in "${!SYNC_SOURCE_REPOS[@]}"; do
    if [[ "${SYNC_SOURCE_REPOS[$i]}" == "$normalized" && "${SYNC_SOURCE_REPO_TYPES[$i]}" == "$type" ]]; then
      print_info_message "Already listed ($type): $normalized"
      return 0
    fi
  done
  SYNC_SOURCE_REPOS+=("$normalized")
  SYNC_SOURCE_REPO_TYPES+=("$type")
  write_sync_source_repos
  case "$type" in
    standard)
      if [[ ! -d "$normalized/rules" && ! -d "$normalized/skills" ]]; then
        print_warning_message "No rules/ or skills/ under $normalized — nothing to sync until you add them"
      fi
      ;;
    skills-root)
      if [[ -z "$(find "$normalized" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)" ]]; then
        print_warning_message "No subfolders under $normalized — nothing to sync until skill dirs appear"
      fi
      ;;
    rules-root)
      if [[ -z "$(find "$normalized" -mindepth 1 -maxdepth 1 -type f -name '*.mdc' -print -quit 2>/dev/null)" ]]; then
        print_warning_message "No *.mdc files under $normalized — nothing to sync until rule files appear"
      fi
      ;;
  esac
  print_success_message "Added sync source ($type): $normalized"
  return 0
}

# Remove repo(s) from sync-sources. With no type, removes every type-entry
# matching the path. With a type, removes only that type-entry. Returns 1 if
# nothing matched.
remove_sync_source_repo() {
  local raw="${1:-}" type="${2:-}" normalized i kept_paths=() kept_types=() found=false
  [[ -n "$raw" ]] || return 1
  if ! normalized="$(normalize_sync_source_repo_path "$raw")"; then
    return 1
  fi
  SYNC_SOURCE_REPOS=()
  SYNC_SOURCE_REPO_TYPES=()
  _read_sync_source_repo_lines
  for i in "${!SYNC_SOURCE_REPO_LINES[@]}"; do
    if [[ "${SYNC_SOURCE_REPO_LINES[$i]}" == "$normalized" ]] \
      && { [[ -z "$type" ]] || [[ "${SYNC_SOURCE_REPO_LINE_TYPES[$i]}" == "$type" ]]; }; then
      found=true
      continue
    fi
    kept_paths+=("${SYNC_SOURCE_REPO_LINES[$i]}")
    kept_types+=("${SYNC_SOURCE_REPO_LINE_TYPES[$i]}")
  done
  if [[ "$found" != true ]]; then
    print_warning_message "Not listed: $normalized${type:+ ($type)}"
    return 1
  fi
  SYNC_SOURCE_REPOS=("${kept_paths[@]}")
  SYNC_SOURCE_REPO_TYPES=("${kept_types[@]}")
  write_sync_source_repos
  print_success_message "Removed sync source: $normalized${type:+ ($type)}"
  return 0
}

# Populate parallel SYNC_SOURCE_REPOS_ALL / SYNC_SOURCE_REPOS_ALL_TYPES:
# primary dotfiles-arch root (type standard) + configured extras.
collect_sync_source_repos() {
  local primary="${1:-}"
  SYNC_SOURCE_REPOS_ALL=()
  SYNC_SOURCE_REPOS_ALL_TYPES=()
  if [[ -n "$primary" ]]; then
    SYNC_SOURCE_REPOS_ALL+=("$primary")
    SYNC_SOURCE_REPOS_ALL_TYPES+=("standard")
  fi
  load_sync_source_repos
  SYNC_SOURCE_REPOS_ALL+=("${SYNC_SOURCE_REPOS[@]}")
  SYNC_SOURCE_REPOS_ALL_TYPES+=("${SYNC_SOURCE_REPO_TYPES[@]}")
}

# Effective directory to scan for a given source (repo_root, type, kind),
# where kind is "rules" or "skills" (stdout). Returns 1 when this
# source/kind combination doesn't apply (e.g. a skills-root source has no
# rules to contribute).
sync_source_effective_dir() {
  local repo_root="${1:-}" type="${2:-}" kind="${3:-}"
  case "$kind:$type" in
    rules:standard) echo "$repo_root/rules" ;;
    rules:rules-root) echo "$repo_root" ;;
    skills:standard) echo "$repo_root/skills" ;;
    skills:skills-root) echo "$repo_root" ;;
    *) return 1 ;;
  esac
}

# Resolve a symlink to an absolute path (works for broken links).
_sync_sources_abs_symlink_target() {
  local entry="${1:-}" target dir
  [[ -L "$entry" ]] || return 1
  target="$(readlink "$entry")"
  [[ -n "$target" ]] || return 1
  if [[ "$target" != /* ]]; then
    dir="$(dirname "$entry")"
    target="$dir/$target"
  fi
  realpath -m "$target"
}

# Link rules/*.mdc from a source into target_dir. Later sources override earlier
# ones. Uses global associative array _sync_rules_linked_names for collision
# tracking. type is standard|rules-root (see sync_source_effective_dir).
sync_rules_from_repo() {
  local repo_root="${1:-}" type="${2:-}" target_dir="${3:-}" rules_dir rule_file rule_name

  rules_dir="$(sync_source_effective_dir "$repo_root" "$type" rules)" || return 0
  [[ -d "$rules_dir" ]] || return 0

  while IFS= read -r -d '' rule_file; do
    rule_name="$(basename "$rule_file")"
    if [[ -n "${_sync_rules_linked_names[$rule_name]:-}" ]]; then
      print_warning_message "Overriding rule $rule_name (was ${_sync_rules_linked_names[$rule_name]}) with $repo_root"
    fi
    if ! head -n1 "$rule_file" | grep -q '^---$'; then
      print_warning_message "$rules_dir/$rule_name has no YAML frontmatter — linking anyway"
    fi
    ln -sfn "$rule_file" "$target_dir/$rule_name"
    print_info_message "Linked: $target_dir/$rule_name"
    _sync_rules_linked_names["$rule_name"]="$repo_root"
    SYNC_RULES_LINKED_COUNT=$((SYNC_RULES_LINKED_COUNT + 1))
  done < <(find "$rules_dir" -mindepth 1 -maxdepth 1 -type f -name '*.mdc' -print0)
}

# Link skills/*/ from a source into target_dir. Later sources override earlier
# ones. Uses global associative array _sync_skills_linked_names for collision
# tracking. type is standard|skills-root (see sync_source_effective_dir).
sync_skills_from_repo() {
  local repo_root="${1:-}" type="${2:-}" target_dir="${3:-}" skills_dir skill_dir skill_name

  skills_dir="$(sync_source_effective_dir "$repo_root" "$type" skills)" || return 0
  [[ -d "$skills_dir" ]] || return 0

  while IFS= read -r -d '' skill_dir; do
    skill_name="$(basename "$skill_dir")"
    if [[ -n "${_sync_skills_linked_names[$skill_name]:-}" ]]; then
      print_warning_message "Overriding skill $skill_name (was ${_sync_skills_linked_names[$skill_name]}) with $repo_root"
    fi
    if [[ ! -f "$skill_dir/SKILL.md" ]]; then
      print_warning_message "$skills_dir/$skill_name has no SKILL.md — linking anyway"
    fi
    ln -sfn "$skill_dir" "$target_dir/$skill_name"
    print_info_message "Linked: $target_dir/$skill_name"
    _sync_skills_linked_names["$skill_name"]="$repo_root"
    SYNC_SKILLS_LINKED_COUNT=$((SYNC_SKILLS_LINKED_COUNT + 1))
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d -print0)
}

# Prune managed symlinks in target_dir for rules or skills (kind = rules|skills).
# A symlink is pruned when it's dangling, or when its resolved parent directory
# is not the effective rules/skills dir of any currently configured source
# (covers both a removed/unlisted source and a source whose type changed).
# Expects SYNC_SOURCE_REPOS_ALL / SYNC_SOURCE_REPOS_ALL_TYPES to already be
# populated (via collect_sync_source_repos).
prune_managed_symlinks() {
  local target_dir="${1:-}" kind="${2:-}" entry resolved parent i eff_dir
  local -A expected_dirs=()

  case "$kind" in
    rules | skills) ;;
    *) return 1 ;;
  esac

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    if eff_dir="$(sync_source_effective_dir "${SYNC_SOURCE_REPOS_ALL[$i]}" "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}" "$kind")"; then
      expected_dirs["$eff_dir"]=1
    fi
  done

  while IFS= read -r -d '' entry; do
    [[ -L "$entry" ]] || continue
    resolved="$(_sync_sources_abs_symlink_target "$entry")"
    [[ -n "$resolved" ]] || continue
    parent="$(dirname "$resolved")"

    if [[ -z "${expected_dirs[$parent]:-}" ]]; then
      print_action_message "Removing symlink from unlisted/removed source ($parent): $entry"
      rm -f "$entry"
      if [[ "$kind" == "rules" ]]; then
        SYNC_RULES_PRUNED_COUNT=$((SYNC_RULES_PRUNED_COUNT + 1))
      else
        SYNC_SKILLS_PRUNED_COUNT=$((SYNC_SKILLS_PRUNED_COUNT + 1))
      fi
      continue
    fi

    [[ -e "$resolved" ]] && continue
    print_action_message "Removing stale $kind symlink: $entry"
    rm -f "$entry"
    if [[ "$kind" == "rules" ]]; then
      SYNC_RULES_PRUNED_COUNT=$((SYNC_RULES_PRUNED_COUNT + 1))
    else
      SYNC_SKILLS_PRUNED_COUNT=$((SYNC_SKILLS_PRUNED_COUNT + 1))
    fi
  done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -print0)
}

# Remove all managed rules/skills symlinks pointing at repo_root's effective
# dir for type (after `dfa-sync-sources remove`).
prune_sync_source_repo_symlinks() {
  local repo_root="${1:-}" type="${2:-}"
  shift 2
  local target_dir entry resolved kind eff_dir

  [[ -n "$repo_root" && -n "$type" ]] || return 0

  for kind in rules skills; do
    eff_dir="$(sync_source_effective_dir "$repo_root" "$type" "$kind")" || continue
    for target_dir in "$@"; do
      [[ -d "$target_dir" ]] || continue
      while IFS= read -r -d '' entry; do
        [[ -L "$entry" ]] || continue
        resolved="$(_sync_sources_abs_symlink_target "$entry")"
        [[ -n "$resolved" ]] || continue
        [[ "$(dirname "$resolved")" == "$eff_dir" ]] || continue
        print_action_message "Removing $kind symlink from removed source: $entry"
        rm -f "$entry"
      done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -print0)
    done
  done
}
