#!/usr/bin/env bash
# Shared link/prune helpers for sync-rules.sh and sync-skills.sh.
# Expects fn-lib.sh (print_*, collect_sync_source_repos, …) to be loaded.

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

# True when repo_root is in SYNC_SOURCE_REPOS_ALL.
_sync_sources_repo_is_configured() {
  local repo_root="${1:-}" root
  for root in "${SYNC_SOURCE_REPOS_ALL[@]}"; do
    [[ "$root" == "$repo_root" ]] && return 0
  done
  return 1
}

# Link rules/*.mdc from repo_root into target_dir. Later repos override earlier ones.
# Uses global associative array _sync_rules_linked_names for collision tracking.
sync_rules_from_repo() {
  local repo_root="${1:-}" target_dir="${2:-}" rules_dir rule_file rule_name

  rules_dir="$repo_root/rules"
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

# Link skills/*/ from repo_root into target_dir. Later repos override earlier ones.
# Uses global associative array _sync_skills_linked_names for collision tracking.
sync_skills_from_repo() {
  local repo_root="${1:-}" target_dir="${2:-}" skills_dir skill_dir skill_name

  skills_dir="$repo_root/skills"
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
prune_managed_symlinks() {
  local target_dir="${1:-}" kind="${2:-}" entry resolved repo_root subdir

  case "$kind" in
    rules) subdir="rules" ;;
    skills) subdir="skills" ;;
    *) return 1 ;;
  esac

  while IFS= read -r -d '' entry; do
    [[ -L "$entry" ]] || continue
    resolved="$(_sync_sources_abs_symlink_target "$entry")"
    [[ -n "$resolved" ]] || continue
    [[ "$resolved" == */"$subdir"/* ]] || continue
    repo_root="$(sync_source_repo_root_from_resolved "$resolved")" || continue

    if ! _sync_sources_repo_is_configured "$repo_root"; then
      print_action_message "Removing symlink from unlisted source ($repo_root): $entry"
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

# Remove all managed rules/skills symlinks pointing into repo_root (after sync-sources remove).
prune_sync_source_repo_symlinks() {
  local repo_root="${1:-}"
  shift
  local target_dir entry resolved kind subdir

  [[ -n "$repo_root" ]] || return 0

  for kind in rules skills; do
    subdir="$kind"
    for target_dir in "$@"; do
      [[ -d "$target_dir" ]] || continue
      while IFS= read -r -d '' entry; do
        [[ -L "$entry" ]] || continue
        resolved="$(_sync_sources_abs_symlink_target "$entry")"
        [[ -n "$resolved" ]] || continue
        [[ "$resolved" == "$repo_root/$subdir"/* ]] || continue
        print_action_message "Removing $kind symlink from removed source: $entry"
        rm -f "$entry"
      done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -print0)
    done
  done
}
