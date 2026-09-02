#!/usr/bin/env bash
# Sync-sources domain: config CRUD (add/remove/list extra rules/skills source
# repos) plus the link/prune helpers used by sync-rules.sh and sync-skills.sh.
# Expects fn-lib.sh (print_*, bootstrap_config_dir) to be loaded.
#
# Each configured source has a type:
#   standard    — repo root has rules/ and/or skills/ (skill dirs) under it,
#                 same layout as dotfiles-arch itself.
#   skills-root — the path itself IS a flat folder of skill dirs (no skills/
#                 subdir). Useful for a subfolder of someone else's skills repo,
#                 e.g. mattpocock/skills/skills/engineering.
#   rules-root  — the path itself IS a flat folder of rule files (no rules/
#                 subdir).
#
# Config file lines: bare "path" means standard (for backwards compatibility);
# "type:path" is explicit. Comments (#) and blank lines are ignored.
#
# Rules go through a per-source build step (build_sync_source_rules) before
# linking: a source's raw rules dir may hold ready-made *.mdc (Cursor format,
# copied as-is) or plain *.md with YAML frontmatter (Cursor-only shorthand,
# auto-detected by extension and converted). The build also derives a
# per-source Claude file — description-stripped bodies of only the
# `alwaysApply: true` rules — since Claude Code has no rules directory of its
# own, only CLAUDE.md @imports. Build output lives under
# rules-build/<slug>/ in the bootstrap config dir and is fully rebuilt on
# every sync, so it can never drift from the source. Skills need no such
# build step — SKILL.md already works unchanged for both tools.

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
      if [[ -z "$(find "$normalized" -mindepth 1 -maxdepth 1 -type f \( -name '*.mdc' -o -name '*.md' \) -print -quit 2>/dev/null)" ]]; then
        print_warning_message "No *.mdc/*.md files under $normalized — nothing to sync until rule files appear"
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

# Filesystem-safe, collision-free slug for a normalized repo path (stdout).
_sync_source_slug() {
  local path="${1:-}"
  path="${path#/}"
  echo "${path//\//-}"
}

# Root of a source's generated rules build output (stdout).
sync_source_rules_build_dir() {
  local repo_root="${1:-}"
  echo "$(bootstrap_config_dir)/rules-build/$(_sync_source_slug "$repo_root")"
}

# The source's own, unconverted rules directory (stdout). Returns 1 when this
# source type has no rules to contribute (e.g. skills-root).
sync_source_raw_rules_dir() {
  local repo_root="${1:-}" type="${2:-}"
  case "$type" in
    standard) echo "$repo_root/rules" ;;
    rules-root) echo "$repo_root" ;;
    *) return 1 ;;
  esac
}

# Effective directory to scan for a given source (repo_root, type, kind),
# where kind is "rules" or "skills" (stdout). Returns 1 when this
# source/kind combination doesn't apply (e.g. a skills-root source has no
# rules to contribute).
#
# For "rules", this is the source's *build output* dir (see
# build_sync_source_rules), not its raw rules dir — every source's rules are
# staged and normalized to .mdc there before anything links to them.
sync_source_effective_dir() {
  local repo_root="${1:-}" type="${2:-}" kind="${3:-}"
  case "$kind:$type" in
    rules:standard | rules:rules-root) echo "$(sync_source_rules_build_dir "$repo_root")/mdc" ;;
    skills:standard) echo "$repo_root/skills" ;;
    skills:skills-root) echo "$repo_root" ;;
    *) return 1 ;;
  esac
}

# Read a frontmatter field (description|alwaysApply|globs) from a rule file's
# YAML block (between the first pair of "---" lines) into stdout.
_sync_rule_frontmatter_field() {
  local file="${1:-}" field="${2:-}" in_fm=0 line
  while IFS= read -r line; do
    if [[ "$in_fm" == 0 && "$line" == "---" ]]; then
      in_fm=1
      continue
    fi
    if [[ "$in_fm" == 1 && "$line" == "---" ]]; then
      break
    fi
    [[ "$in_fm" == 1 ]] || continue
    if [[ "$line" == "$field:"* ]]; then
      line="${line#"$field":}"
      line="${line# }"
      echo "$line"
      return 0
    fi
  done <"$file"
}

# Body of a rule file: everything after the closing frontmatter delimiter
# (preserves any "---" horizontal rules in the body itself).
_sync_rule_body() {
  awk 'BEGIN{fm=0} /^---$/{if(fm<2){fm++;next}} fm>=2{print}' "${1:-}"
}

# Build (from scratch) one source's rules-build dir: rules-build/<slug>/mdc/
# (Cursor-ready .mdc, one per rule) and rules-build/<slug>/claude-rules.md
# (bodies of only the alwaysApply:true rules, concatenated, frontmatter
# stripped — omitted entirely when the source has none). type is
# standard|rules-root; no-ops for other types (e.g. skills-root).
build_sync_source_rules() {
  local repo_root="${1:-}" type="${2:-}" raw_dir build_dir mdc_out claude_out
  local rule_file base description always_apply globs body

  raw_dir="$(sync_source_raw_rules_dir "$repo_root" "$type")" || return 0
  build_dir="$(sync_source_rules_build_dir "$repo_root")"
  mdc_out="$build_dir/mdc"
  claude_out="$build_dir/claude-rules.md"

  rm -rf "$build_dir"
  mkdir -p "$mdc_out"

  [[ -d "$raw_dir" ]] || return 0

  local claude_tmp
  claude_tmp="$(mktemp)"
  local claude_rule_count=0

  while IFS= read -r -d '' rule_file; do
    base="$(basename "$rule_file")"
    base="${base%.*}"

    description="$(_sync_rule_frontmatter_field "$rule_file" description)"
    always_apply="$(_sync_rule_frontmatter_field "$rule_file" alwaysApply)"
    globs="$(_sync_rule_frontmatter_field "$rule_file" globs)"
    body="$(_sync_rule_body "$rule_file")"

    case "$rule_file" in
      *.mdc)
        cp "$rule_file" "$mdc_out/$base.mdc"
        ;;
      *)
        {
          echo "---"
          echo "description: ${description:-Rule}"
          [[ -n "$globs" ]] && echo "globs: ${globs}"
          echo "alwaysApply: ${always_apply:-false}"
          echo "---"
          echo "$body"
        } >"$mdc_out/$base.mdc"
        ;;
    esac

    if [[ "$always_apply" =~ ^true[[:space:]]*$ ]]; then
      {
        echo "## ${description:-$base}"
        echo ""
        echo "$body"
        echo ""
      } >>"$claude_tmp"
      claude_rule_count=$((claude_rule_count + 1))
    fi
  done < <(find "$raw_dir" -mindepth 1 -maxdepth 1 -type f \( -name '*.mdc' -o -name '*.md' \) ! -iname 'readme.md' -print0)

  if [[ "$claude_rule_count" -gt 0 ]]; then
    {
      echo "<!-- managed-by: dotfiles-arch dfa-sync-rules — do not edit; source: $repo_root -->"
      echo ""
      cat "$claude_tmp"
    } >"$claude_out"
  fi
  rm -f "$claude_tmp"
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
    if [[ -e "$target_dir/$rule_name" && ! -L "$target_dir/$rule_name" ]]; then
      print_action_message "Removing local (non-symlinked) rule, superseded by source: $target_dir/$rule_name"
      rm -rf "${target_dir:?}/$rule_name"
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
    if [[ -e "$target_dir/$skill_name" && ! -L "$target_dir/$skill_name" ]]; then
      print_action_message "Removing local (non-symlinked) skill, superseded by source: $target_dir/$skill_name"
      rm -rf "${target_dir:?}/$skill_name"
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
# dir for type (after `dfa-sync-sources remove`), plus that source's Claude
# rules import/symlink and its rules-build staging dir.
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

  _remove_claude_rule_import "$repo_root"
  rm -rf "$(sync_source_rules_build_dir "$repo_root")"
}

# ~/.claude/CLAUDE.md import line for a source's generated Claude rules file.
_claude_rule_import_line() {
  echo "@dfa-rules-$(_sync_source_slug "${1:-}").md"
}

# Path to a source's generated-and-symlinked Claude rules file.
_claude_rule_dest() {
  echo "$USER_HOME_DIR/.claude/dfa-rules-$(_sync_source_slug "${1:-}").md"
}

# Idempotently append the import line for repo_root to ~/.claude/CLAUDE.md.
# Only ever adds/removes its own "@dfa-rules-*.md" lines — never touches any
# other content, since CLAUDE.md is user-owned.
_ensure_claude_import_line() {
  local repo_root="${1:-}" claude_md import_line
  claude_md="$USER_HOME_DIR/.claude/CLAUDE.md"
  import_line="$(_claude_rule_import_line "$repo_root")"

  if [[ ! -e "$claude_md" ]]; then
    mkdir -p "$(dirname "$claude_md")"
    printf '%s\n' "$import_line" >"$claude_md"
    return 0
  fi
  grep -qxF "$import_line" "$claude_md" 2>/dev/null && return 0
  printf '\n%s\n' "$import_line" >>"$claude_md"
}

# Remove repo_root's generated Claude rules symlink and its CLAUDE.md import
# line (if present).
_remove_claude_rule_import() {
  local repo_root="${1:-}" dest claude_md import_line
  dest="$(_claude_rule_dest "$repo_root")"
  claude_md="$USER_HOME_DIR/.claude/CLAUDE.md"
  import_line="$(_claude_rule_import_line "$repo_root")"

  [[ -e "$dest" || -L "$dest" ]] && rm -f "$dest"
  [[ -f "$claude_md" ]] || return 0
  grep -qxF "$import_line" "$claude_md" 2>/dev/null || return 0
  grep -vxF "$import_line" "$claude_md" >"$claude_md.tmp" && mv "$claude_md.tmp" "$claude_md"
}

# Symlink repo_root's generated claude-rules.md (if it produced one) to
# ~/.claude/dfa-rules-<slug>.md and ensure CLAUDE.md imports it; otherwise
# remove both. Call after build_sync_source_rules. type is standard|rules-root.
sync_claude_rule_import() {
  local repo_root="${1:-}" type="${2:-}" claude_out dest

  case "$type" in
    standard | rules-root) ;;
    *) return 0 ;;
  esac

  claude_out="$(sync_source_rules_build_dir "$repo_root")/claude-rules.md"
  if [[ -f "$claude_out" ]]; then
    dest="$(_claude_rule_dest "$repo_root")"
    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      print_action_message "Removing local (non-symlinked) Claude rules file, superseded by source: $dest"
      rm -rf "$dest"
    fi
    ln -sfn "$claude_out" "$dest"
    _ensure_claude_import_line "$repo_root"
    print_info_message "Linked: $dest"
  else
    _remove_claude_rule_import "$repo_root"
  fi
}

# Remove Claude rules symlinks/import lines for any dfa-rules-*.md file in
# ~/.claude that no longer corresponds to a currently active, rules-capable
# source (covers a removed/unlisted source, and a source that no longer has
# any alwaysApply rules). Expects SYNC_SOURCE_REPOS_ALL /
# SYNC_SOURCE_REPOS_ALL_TYPES to already be populated.
prune_claude_rule_imports() {
  local dir="$USER_HOME_DIR/.claude" entry slug i repo_type
  local -A expected_slugs=()

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    repo_type="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
    case "$repo_type" in
      standard | rules-root) ;;
      *) continue ;;
    esac
    if [[ -f "$(sync_source_rules_build_dir "${SYNC_SOURCE_REPOS_ALL[$i]}")/claude-rules.md" ]]; then
      expected_slugs["$(_sync_source_slug "${SYNC_SOURCE_REPOS_ALL[$i]}")"]=1
    fi
  done

  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' entry; do
    slug="$(basename "$entry")"
    slug="${slug#dfa-rules-}"
    slug="${slug%.md}"
    [[ -n "${expected_slugs[$slug]:-}" ]] && continue
    print_action_message "Removing stale Claude rules import: $entry"
    rm -f "$entry"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -name 'dfa-rules-*.md' -print0)

  # Drop CLAUDE.md import lines for slugs with no surviving symlink.
  local claude_md="$dir/CLAUDE.md" line slug_from_line kept_tmp
  [[ -f "$claude_md" ]] || return 0
  kept_tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      @dfa-rules-*.md)
        slug_from_line="${line#@dfa-rules-}"
        slug_from_line="${slug_from_line%.md}"
        if [[ -n "${expected_slugs[$slug_from_line]:-}" ]]; then
          printf '%s\n' "$line" >>"$kept_tmp"
        fi
        ;;
      *)
        printf '%s\n' "$line" >>"$kept_tmp"
        ;;
    esac
  done <"$claude_md"
  mv "$kept_tmp" "$claude_md"
}

# Remove any rules-build/<slug>/ dir that doesn't belong to a currently
# configured source — covers a source dropped by hand-editing sync-sources
# (rather than via `dfa-sync-sources remove`, which already cleans up its own
# source's build dir immediately). Expects SYNC_SOURCE_REPOS_ALL to already be
# populated.
prune_orphaned_rules_build_dirs() {
  local build_root entry slug i
  build_root="$(bootstrap_config_dir)/rules-build"
  local -A expected_slugs=()

  [[ -d "$build_root" ]] || return 0

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    expected_slugs["$(_sync_source_slug "${SYNC_SOURCE_REPOS_ALL[$i]}")"]=1
  done

  while IFS= read -r -d '' entry; do
    slug="$(basename "$entry")"
    [[ -n "${expected_slugs[$slug]:-}" ]] && continue
    print_action_message "Removing orphaned rules-build dir (source no longer configured): $entry"
    rm -rf "$entry"
  done < <(find "$build_root" -mindepth 1 -maxdepth 1 -type d -print0)
}
