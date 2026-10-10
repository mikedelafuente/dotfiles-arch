#!/bin/bash

# --------------------------
# Update npm-installed agent CLIs and recognized user-native Claude
# --------------------------
# Existing npm Claude and Codex keep user npm maintenance. New Ubuntu
# Claude uses verified native acquisition; recognized native Claude uses its
# own updater without NVM/npm or sudo. Visible DISABLE_UPDATES policy defers
# either Claude owner without changing settings.
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
deferred=0
load_nvm || true

for harness in claude codex opencode; do
  if ! command -v "$harness" &>/dev/null; then
    print_info_message "$harness not installed — skip"
    continue
  fi
  owner="$(harness_installed_owner "$harness")" || {
    print_error_message "Cannot identify $harness update owner; retained"
    ((failed++)) || true
    continue
  }
  if [[ "$harness" == claude && "$owner" != native ]]; then
    policy_status=0
    claude_updates_allowed || policy_status=$?
    if [[ "$policy_status" == 2 ]]; then
      print_info_message 'Claude updates deferred by user/managed DISABLE_UPDATES; owner retained'
      ((deferred++)) || true
      continue
    elif [[ "$policy_status" != 0 ]]; then
      print_error_message 'Cannot read Claude update policy; owner retained'
      ((failed++)) || true
      continue
    fi
  fi
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
  if npm update -g "$package"; then
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

print_info_message "Agent CLI updates: $updated checked, $deferred policy-deferred, $failed failed"
((failed > 0)) && exit 1
exit 0
