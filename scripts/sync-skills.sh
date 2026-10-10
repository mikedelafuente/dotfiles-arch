#!/bin/bash
# --------------------------
# Sync personal Claude/Cursor/Codex/Pi skills
# --------------------------
# Symlinks each skill folder from dotfiles-arch and any extra repos registered
# via dfa-sync-sources recursively into the native skills directories for Claude, Cursor,
# detected Codex, and Pi, and prunes managed symlinks when the source
# is removed or the repo is unlisted. Standard-type sources contribute their
# skills/ subfolder; skills-root sources contribute their own folder directly
# (see dfa-sync-sources --type). Only ever touches symlinks whose target is a
# configured source's effective skills dir — real directories elsewhere are
# left alone. Pi settings reconciliation belongs to the standalone resource
# owner; Copy preflight blocks duplicate resource routes. Safe to re-run.

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
# Stable deployment owns linking once installed (and on actual source checkouts).
# Non-git supplied fixtures retain the legacy isolated sync interfaces.
if [[ -L "$USER_HOME_DIR/.local/share/workstation/config" ]]; then
  exec python3 "$DF_SCRIPT_DIR/deployment.py" deploy
elif [[ -e "$REPO_ROOT/.git" ]]; then
  exec python3 "$DF_SCRIPT_DIR/deployment.py" deploy --source "$REPO_ROOT"
fi

TARGET_DIRS=("$USER_HOME_DIR/.claude/skills" "$USER_HOME_DIR/.cursor/skills")
if command -v codex &>/dev/null; then
  TARGET_DIRS+=("$(codex_home_dir)/skills")
fi
TARGET_DIRS+=("$(pi_agent_dir)/skills")

print_line_break "Syncing skills"

collect_sync_source_repos "$REPO_ROOT"
if [[ ${#SYNC_SOURCE_REPOS_ALL[@]} -eq 0 ]]; then
  print_warning_message "No skill sources configured — nothing to sync"
  exit 0
fi

SYNC_SKILLS_LINKED_COUNT=0
SYNC_SKILLS_PRUNED_COUNT=0

# Discover and validate the complete mapping before changing any target.
skill_roots=()
discovery_options=()
# Extra sources retain their relative order; primary skills always have final priority.
for ((i=1; i<${#SYNC_SOURCE_REPOS_ALL[@]}; i++)); do
  if skills_dir="$(sync_source_effective_dir "${SYNC_SOURCE_REPOS_ALL[$i]}" "${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}" skills)" && [[ -d "$skills_dir" ]]; then
    skill_roots+=("$skills_dir")
    key="${SYNC_SOURCE_REPOS_ALL_TYPES[$i]}:${SYNC_SOURCE_REPOS_ALL[$i]}"
    if [[ "${SYNC_SOURCE_OVERWRITABLE[$key]:-false}" == true ]]; then
      discovery_options+=(--overwritable "$skills_dir")
    fi
  fi
done
[[ ! -d "$REPO_ROOT/skills" ]] || skill_roots+=("$REPO_ROOT/skills")
manifest="$(mktemp)" || exit 1
if ! python3 "$DF_SCRIPT_DIR/skill_discovery.py" "${discovery_options[@]}" "${skill_roots[@]}" >"$manifest"; then
  rm -f "$manifest"
  exit 1
fi
mapfile -d '' -t SYNC_SKILL_DIRS <"$manifest"
rm -f "$manifest"
# Check every destination before linking, preserving unrelated entries.
for target_dir in "${TARGET_DIRS[@]}"; do
  if [[ -L "$target_dir" || -L "${target_dir%/*}" ]]; then
    print_error_message "Preserving redirected skill directory: $target_dir"
    exit 1
  fi
  for skill_dir in "${SYNC_SKILL_DIRS[@]}"; do
    dest="$target_dir/${skill_dir##*/}"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
      print_error_message "Preserving existing real skill entry: $dest"
      exit 1
    fi
    if [[ -L "$dest" ]]; then
      resolved="$(_sync_skill_link_target "$dest")"
      owned=false
      for root in "${skill_roots[@]}"; do
        if [[ "$resolved" == "$root/"* && "${resolved##*/}" == "${dest##*/}" ]]; then
          owned=true
          break
        fi
      done
      if [[ "$owned" != true ]]; then
        print_error_message "Preserving unrelated skill symlink: $dest"
        exit 1
      fi
    fi
  done
done

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"
  declare -A _sync_skills_linked_names=()

  sync_skill_dirs "$target_dir" || exit 1

  prune_managed_symlinks "$target_dir" skills
done

print_success_message "Skills synced: $SYNC_SKILLS_LINKED_COUNT linked, $SYNC_SKILLS_PRUNED_COUNT pruned"
