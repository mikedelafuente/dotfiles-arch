#!/bin/bash

# --------------------------
# Update npm-installed agent CLIs and recognized user-native Claude
# --------------------------
# claude, codex, and pi are installed via `npm install -g` (setup-claude.sh /
# setup-codex.sh / setup-pi.sh), which only installs when missing — it never
# upgrades an existing install. This script covers that gap with
# `npm update -g` for whichever of those CLIs are actually installed.
# Recognized native Claude uses its own updater, without NVM/npm or sudo.
#
# opencode uses native updates on Arch and user npm on Ubuntu. Unknown
# launchers fail rather than silently acquiring another source.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

[[ "$EUID" != 0 ]] || { print_error_message 'Run CLI updates as the user, without sudo'; exit 1; }
print_line_break "Update agent CLIs through their selected owners"
updated=0
failed=0
load_nvm || true

for harness in claude codex pi opencode; do
  if ! command -v "$harness" &>/dev/null; then
    print_info_message "$harness not installed — skip"
    continue
  fi
  owner="$(harness_installed_owner "$harness")" || {
    print_error_message "Cannot identify $harness update owner; retained"
    ((failed++)) || true
    continue
  }
  case "$owner" in
    native)
      print_info_message "$harness is native-package-owned — dfa-update-system handles it"
      continue ;;
    claude-native)
      if claude update; then
        ((updated++)) || true
      else
        print_error_message 'Failed to update native Claude'
        ((failed++)) || true
      fi
      continue ;;
  esac
  package="$(harness_npm_package "$harness")" || exit 1
  before_version="$("$harness" --version 2>/dev/null || true)"
  print_action_message "Updating $harness ($package) via user npm"
  # Pi's lifecycle scripts stay blocked on refresh as well as acquisition.
  npm_args=()
  [[ "$harness" != pi ]] || npm_args+=(--ignore-scripts)
  if npm update -g "${npm_args[@]}" "$package"; then
    after_version="$("$harness" --version 2>/dev/null || true)"
    if [[ -n "$after_version" ]]; then
      print_success_message "$harness checked: $before_version -> $after_version"
      ((updated++)) || true
    else
      print_error_message "$harness unavailable after npm refresh"
      ((failed++)) || true
    fi
  else
    print_error_message "Failed to update $harness ($package)"
    ((failed++)) || true
  fi
done

print_info_message "Agent CLI updates: $updated checked, $failed failed"
((failed > 0)) && exit 1
exit 0
