#!/usr/bin/env bash
# Sync-sources domain: config CRUD (add/remove/list extra rules/skills/extensions
# source repos) plus the link/prune helpers used by the sync scripts.
# Expects fn-lib.sh (print_*, bootstrap_config_dir) to be loaded.
#
# Each configured source has a type:
#   standard    — repo root has rules/, skills/, and/or extensions/ under it
#                  (Pi's own repo may use pi/extensions/),
#                 same layout as dotfiles-arch itself.
#   skills-root — the path itself IS a flat folder of skill dirs (no skills/
#                 subdir). Useful for a subfolder of someone else's skills repo,
#                 e.g. mattpocock/skills/skills/engineering.
#   rules-root  — the path itself IS a flat folder of rule files (no rules/
#                 subdir).
#   extensions-root — the path itself IS a flat folder of Pi extensions (no
#                     extensions/ subdir).
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
# build step — SKILL.md already works unchanged for all three tools.
#
# Codex and Pi are wired in alongside Claude and Cursor:
#   - Codex: ~/.codex/skills and ~/.codex/AGENTS.md (or CODEX_HOME), when the
#     `codex` CLI is detected.
#   - skills: ~/.pi/agent/skills/<name> (Pi discovers its own global skills dir
#     natively — no settings needed). A legacy Pi settings `skills` array that
#     pointed at ~/.claude/skills / ~/.codex/skills is pruned so Pi never
#     discovers the same skill twice (see prune_pi_settings_skill_paths).
#   - rules: ~/.pi/agent/AGENTS.md — the single raw global agent file Pi reads
#     at startup. Pi has no @import mechanism, so the alwaysApply bodies of
#     every active source are concatenated into one regenerated file
#     (rules-build/pi-agents.md) and symlinked there (see
#     build_pi_agents_file / sync_pi_agents_file).

SYNC_SOURCE_KNOWN_TYPES=(standard skills-root rules-root extensions-root)

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
    rules-root:*)      type="rules-root"      path="${line#rules-root:}" ;;
    extensions-root:*) type="extensions-root" path="${line#extensions-root:}" ;;
    standard:*)        type="standard"        path="${line#standard:}" ;;
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
    echo "# Types: standard (default, has rules/ + skills/ + extensions/ subdirs;"
    echo "# skills-root (path is itself a flat folder of skill dirs), rules-root"
    echo "# dotfiles-arch uses pi/extensions/), rules-root (path is itself a flat folder"
    echo "# of *.mdc files), extensions-root (path is itself a flat folder of Pi extensions)."
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
      if [[ ! -d "$normalized/rules" && ! -d "$normalized/skills" && ! -d "$normalized/extensions" && ! -d "$normalized/pi/extensions" ]]; then
        print_warning_message "No rules/, skills/, extensions/, or pi/extensions/ under $normalized — nothing to sync until you add them"
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
    extensions-root)
      if [[ -z "$(find "$normalized" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print -quit 2>/dev/null)" ]]; then
        print_warning_message "No extension entries under $normalized — nothing to sync until extensions appear"
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
# where kind is "rules", "skills", or "extensions" (stdout). Returns 1 when
# this source/kind combination doesn't apply (e.g. a skills-root source has no
# rules or extensions to contribute).
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
    extensions:standard)
      # Pi's own extensions live with the rest of its config under pi/. Keep
      # the root-level layout as a compatibility fallback for external sources.
      if [[ -d "$repo_root/pi/extensions" ]]; then
        echo "$repo_root/pi/extensions"
      else
        echo "$repo_root/extensions"
      fi
      ;;
    extensions:extensions-root) echo "$repo_root" ;;
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

# Link extension files/directories from a source into Pi's extensions dir. Later
# sources override earlier ones by basename. Extensions are intentionally linked
# as entries rather than copied so edits remain in their source repo.
sync_extensions_from_repo() {
  local repo_root="${1:-}" type="${2:-}" target_dir="${3:-}" extensions_dir entry extension_name

  extensions_dir="$(sync_source_effective_dir "$repo_root" "$type" extensions)" || return 0
  [[ -d "$extensions_dir" ]] || return 0

  while IFS= read -r -d '' entry; do
    extension_name="$(basename "$entry")"
    if [[ -n "${_sync_extensions_linked_names[$extension_name]:-}" ]]; then
      print_warning_message "Overriding extension $extension_name (was ${_sync_extensions_linked_names[$extension_name]}) with $repo_root"
    fi
    if [[ -e "$target_dir/$extension_name" && ! -L "$target_dir/$extension_name" ]]; then
      print_action_message "Removing local (non-symlinked) extension, superseded by source: $target_dir/$extension_name"
      rm -rf "${target_dir:?}/$extension_name"
    fi
    ln -sfn "$entry" "$target_dir/$extension_name"
    print_info_message "Linked: $target_dir/$extension_name"
    _sync_extensions_linked_names["$extension_name"]="$repo_root"
    SYNC_EXTENSIONS_LINKED_COUNT=$((SYNC_EXTENSIONS_LINKED_COUNT + 1))
  done < <(find "$extensions_dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) -print0)
}

# Prune managed extension symlinks whose source is no longer configured.
prune_managed_extension_symlinks() {
  local target_dir="${1:-}" entry resolved parent i eff_dir
  local -A expected_dirs=()

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    if eff_dir="$(sync_source_effective_dir "${SYNC_SOURCE_REPOS_ALL[$i]}" "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}" extensions)"; then
      expected_dirs["$eff_dir"]=1
    fi
  done

  while IFS= read -r -d '' entry; do
    [[ -L "$entry" ]] || continue
    resolved="$(_sync_sources_abs_symlink_target "$entry")"
    [[ -n "$resolved" ]] || continue
    parent="$(dirname "$resolved")"
    if [[ ! -e "$entry" || -z "${expected_dirs[$parent]:-}" ]]; then
      print_action_message "Removing stale extension symlink: $entry"
      rm -f "$entry"
      SYNC_EXTENSIONS_PRUNED_COUNT=$((SYNC_EXTENSIONS_PRUNED_COUNT + 1))
    fi
  done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -type l -print0)
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

# Pi (pi-coding-agent) parity helpers.
#
# Pi discovers global skills natively under its agent dir (~/.pi/agent by
# default; honor PI_CODING_AGENT_DIR when set, so a relocated agent dir keeps
# working) and reads its global rules from a single raw AGENTS.md there — no
# @import support, so the alwaysApply bodies of every active source must be
# concatenated into one file rather than referenced.

# Pi's global agent dir (stdout). Defaults to ~/.pi/agent; respects
# PI_CODING_AGENT_DIR so sync targets the same dir pi actually reads.
pi_agent_dir() {
  echo "${PI_CODING_AGENT_DIR:-$USER_HOME_DIR/.pi/agent}"
}

# Codex's global agent dir (stdout). Defaults to ~/.codex; respect CODEX_HOME
# so the sync follows the directory used by the installed Codex CLI.
codex_home_dir() {
  echo "${CODEX_HOME:-$USER_HOME_DIR/.codex}"
}

# ~/.pi/agent/settings.json path (stdout).
pi_settings_file() {
  echo "$(pi_agent_dir)/settings.json"
}

# Remove dfa-managed harness skill dirs from Pi settings' `skills` array.
# Before Pi gained its own global skills dir, this was wired manually to
# ~/.claude/skills and ~/.codex/skills; dfa-sync-skills now mirrors the same
# sources into ~/.pi/agent/skills natively, so leaving those entries would make
# Pi discover every skill twice and warn about name collisions at each startup.
# Only ever removes those two exact entries (tilde and $HOME-expanded forms);
# any other skills entries and all other settings are preserved byte-for-byte
# apart from re-serialization.
prune_pi_settings_skill_paths() {
  local file removed
  file="$(pi_settings_file)"
  [[ -f "$file" ]] || return 0
  if ! command -v python3 &>/dev/null; then
    print_warning_message "python3 not found — cannot prune Pi settings.json (remove its skills array manually)"
    return 1
  fi
  removed="$(python3 - "$file" <<'PY'
import json
import os
import sys

path = sys.argv[1]
managed = {"~/.claude/skills", "~/.codex/skills"}
managed_expanded = {os.path.normpath(os.path.expandvars(os.path.expanduser(p))) for p in managed}


def is_managed(value):
    return (
        isinstance(value, str)
        and os.path.normpath(os.path.expandvars(os.path.expanduser(value))) in managed_expanded
    )

try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError):
    sys.exit(0)

skills = data.get("skills")
if not isinstance(skills, list):
    sys.exit(0)

removed = sorted({s for s in skills if is_managed(s)})
if not removed:
    sys.exit(0)

kept = [s for s in skills if not is_managed(s)]
if kept:
    data["skills"] = kept
else:
    data.pop("skills", None)

with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")

print(", ".join(removed))
PY
)"
  if [[ -n "$removed" ]]; then
    print_info_message "Pruned dfa-managed skill dirs from Pi settings: $removed"
  fi
}

# Staging file that becomes Pi's global AGENTS.md (stdout): the alwaysApply
# bodies of every active rules-capable source, concatenated. Lives at the root
# of rules-build/ so prune_orphaned_rules_build_dirs (which only scans
# rules-build/<slug>/) never mistakes it for a source's build dir.
pi_agents_build_file() {
  echo "$(bootstrap_config_dir)/rules-build/pi-agents.md"
}

# Regenerate pi_agents_build_file from every active rules-capable source's
# generated claude-rules.md (frontmatter-stripped alwaysApply bodies only, with
# each source's own managed header included). Omitted entirely when no source
# produced alwaysApply rules. Expects SYNC_SOURCE_REPOS_ALL /
# SYNC_SOURCE_REPOS_ALL_TYPES to already be populated (via
# collect_sync_source_repos).
build_pi_agents_file() {
  local out tmp src_count=0 i repo_root repo_type f
  out="$(pi_agents_build_file)"
  tmp="$(mktemp)"

  for i in "${!SYNC_SOURCE_REPOS_ALL[@]}"; do
    repo_root="${SYNC_SOURCE_REPOS_ALL[$i]}"
    repo_type="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}"
    case "$repo_type" in
      standard | rules-root) ;;
      *) continue ;;
    esac
    f="$(sync_source_rules_build_dir "$repo_root")/claude-rules.md"
    [[ -f "$f" ]] || continue
    if ((src_count > 0)); then
      printf '\n---\n\n' >>"$tmp"
    fi
    printf '<!-- source: %s -->\n\n' "$repo_root" >>"$tmp"
    cat "$f" >>"$tmp"
    src_count=$((src_count + 1))
  done

  if ((src_count == 0)); then
    rm -f "$tmp" "$out"
    return 0
  fi

  {
    echo "<!-- managed-by: dotfiles-arch dfa-sync-rules — do not edit; regenerated from source rules -->"
    echo ""
    cat "$tmp"
  } >"$out"
  rm -f "$tmp"
}

# Symlink Pi's global agent file ~/.pi/agent/AGENTS.md to the regenerated
# pi-agents.md; when no source produced alwaysApply rules, remove it instead.
# Only ever manages a file that is ours — a symlink resolving into
# rules-build/, or a real file carrying the dfa-sync-rules marker. A
# user-written AGENTS.md is left untouched with a warning.
sync_pi_agents_file() {
  local dir dest out resolved marker
  dir="$(pi_agent_dir)"
  dest="$dir/AGENTS.md"
  out="$(pi_agents_build_file)"

  if [[ -f "$out" ]]; then
    mkdir -p "$dir"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      marker="$(head -n1 "$dest" 2>/dev/null || true)"
      if [[ "$marker" != *'managed-by: dotfiles-arch dfa-sync-rules'* ]]; then
        print_warning_message "Leaving user-written Pi agent file (no dfa-sync-rules marker): $dest"
        return 0
      fi
      print_action_message "Removing local (non-symlinked) Pi agent file, superseded by source: $dest"
      rm -rf "$dest"
    fi
    ln -sfn "$out" "$dest"
    print_info_message "Linked: $dest"
    return 0
  fi

  # No alwaysApply rules anywhere — remove ours if present, leave user files.
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    return 0
  fi
  if [[ -L "$dest" ]]; then
    resolved="$(_sync_sources_abs_symlink_target "$dest")"
    if [[ "$resolved" == "$(bootstrap_config_dir)/rules-build/"* ]]; then
      print_action_message "Removing stale Pi agent file: $dest"
      rm -f "$dest"
    fi
    return 0
  fi
  marker="$(head -n1 "$dest" 2>/dev/null || true)"
  if [[ "$marker" == *'managed-by: dotfiles-arch dfa-sync-rules'* ]]; then
    print_action_message "Removing stale Pi agent file: $dest"
    rm -f "$dest"
  fi
}

# Symlink the generated global AGENTS.md into Codex's home when the Codex CLI
# is installed. Preserve a user-written file unless it carries our marker.
sync_codex_agents_file() {
  local dir dest out resolved marker
  command -v codex &>/dev/null || return 0
  dir="$(codex_home_dir)"
  dest="$dir/AGENTS.md"
  out="$(pi_agents_build_file)"

  if [[ -f "$out" ]]; then
    mkdir -p "$dir"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      marker="$(head -n1 "$dest" 2>/dev/null || true)"
      if [[ "$marker" != *'managed-by: dotfiles-arch dfa-sync-rules'* ]]; then
        print_warning_message "Leaving user-written Codex agent file (no dfa-sync-rules marker): $dest"
        return 0
      fi
      rm -f "$dest"
    fi
    ln -sfn "$out" "$dest"
    print_info_message "Linked: $dest"
    return 0
  fi

  [[ -e "$dest" || -L "$dest" ]] || return 0
  if [[ -L "$dest" ]]; then
    resolved="$(_sync_sources_abs_symlink_target "$dest")"
    if [[ "$resolved" == "$(bootstrap_config_dir)/rules-build/"* ]]; then
      print_action_message "Removing stale Codex agent file: $dest"
      rm -f "$dest"
    fi
    return 0
  fi
  marker="$(head -n1 "$dest" 2>/dev/null || true)"
  if [[ "$marker" == *'managed-by: dotfiles-arch dfa-sync-rules'* ]]; then
    print_action_message "Removing stale Codex agent file: $dest"
    rm -f "$dest"
  fi
}

# Rebuild + re-link Pi's global AGENTS.md from the currently configured sources
# (primary + extras still listed). Used by `dfa-sync-sources remove` so a
# removed source's alwaysApply rules disappear from Pi immediately rather than
# at the next dfa-sync-rules run.
refresh_pi_agent_rules() {
  local primary="${1:-}"
  collect_sync_source_repos "$primary"
  build_pi_agents_file
  sync_pi_agents_file
  sync_codex_agents_file
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
