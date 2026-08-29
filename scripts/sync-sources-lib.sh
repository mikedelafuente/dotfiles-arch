#!/usr/bin/env bash
# Shared link/prune helpers for sync-rules.sh and sync-skills.sh.
# Expects fn-lib.sh (print_*, collect_sync_source_repos, sync_source_effective_dir, …) to be loaded.

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
# dir for type (after `dela-sync-sources remove`).
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
