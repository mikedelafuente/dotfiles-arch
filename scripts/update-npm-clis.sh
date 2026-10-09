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
# opencode is deliberately excluded — it's a pacman package
# (setup-opencode.sh), so it's already refreshed by dfa-update-system.
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# harness id -> npm package name (kept in sync by hand with setup-claude.sh /
# setup-codex.sh / setup-pi.sh)
declare -A NPM_HARNESS_PACKAGES=(
  [claude]="@anthropic-ai/claude-code"
  [codex]="@openai/codex"
  [pi]="@earendil-works/pi-coding-agent"
)

print_line_break "Update agent CLIs (npm / native Claude)"

updated=0
failed=0
native_claude=false
claude_launcher="$(type -P claude || true)"
claude_resolved="$(readlink -f "$claude_launcher" || true)"
if claude_native_owns_launcher "$USER_HOME_DIR/.local/share/claude" "$claude_resolved"; then
  native_claude=true
  print_action_message "Updating native Claude through its selected owner (claude update)"
  if "$claude_launcher" update; then
    ((updated++)) || true
  else
    print_error_message "Failed to update native Claude"
    ((failed++)) || true
  fi
fi

if ! load_nvm || ! command -v npm &>/dev/null; then
  print_info_message "NVM/npm not available — skip npm CLI updates"
  ((failed == 0)) && exit 0
  exit 1
fi

npm_root="$(npm root -g)" || {
  print_error_message "Cannot determine npm's global package owner"
  exit 1
}

for harness in claude codex pi; do
  [[ "$harness" != claude || "$native_claude" != true ]] || continue
  package="${NPM_HARNESS_PACKAGES[$harness]}"

  if ! command -v "$harness" &>/dev/null; then
    print_info_message "$harness not installed — skip"
    continue
  fi

  package_dir="$(readlink -f "$npm_root/$package" || true)"
  launcher="$(readlink -f "$(type -P "$harness")" || true)"
  if ! npm_harness_owns_launcher "$package_dir" "$launcher"; then
    print_error_message "Source conflict: $harness launcher is not owned by $package in this npm prefix; retained. Use its selected update owner."
    ((failed++)) || true
    continue
  fi

  before_version="$("$harness" --version 2>/dev/null || true)"
  print_action_message "Updating $harness ($package) via npm"
  if npm update -g "$package"; then
    after_version="$("$harness" --version 2>/dev/null || true)"
    if [[ -n "$after_version" && "$after_version" != "$before_version" ]]; then
      print_success_message "$harness updated: $before_version -> $after_version"
    else
      print_success_message "$harness already up to date ($after_version)"
    fi
    ((updated++)) || true
  else
    print_error_message "Failed to update $harness ($package)"
    ((failed++)) || true
  fi
done

print_info_message "Agent CLI updates: $updated checked, $failed failed"
((failed > 0)) && exit 1
exit 0
