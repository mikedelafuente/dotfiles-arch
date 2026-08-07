#!/bin/bash
# --------------------------
# Shared profile setup runner
# --------------------------
# Used by bootstrap.sh and sync.sh so the script list cannot drift.
#
# Required env:
#   SETUP_PROFILE   work|personal
# Optional env:
#   FULL_NAME / EMAIL_ADDRESS   (skips setup-git.sh if either missing)
#   SETUP_CONTINUE_ON_ERROR     true (default) | false  — abort on first failure
#
# Exit status: 0 if all succeeded, 1 if any script failed (when continuing).

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

SETUP_CONTINUE_ON_ERROR="${SETUP_CONTINUE_ON_ERROR:-true}"

if ! validate_bootstrap_profile; then
  print_error_message "SETUP_PROFILE must be 'work' or 'personal' (got: ${SETUP_PROFILE:-unset})"
  exit 1
fi

print_line_break "Profile setup: $SETUP_PROFILE"

SETUP_FAILURES=()

run_setup() {
  local script="$1"
  shift || true
  if [[ ! -f "$DF_SCRIPT_DIR/$script" ]]; then
    print_warning_message "Missing $script — skipped"
    return 0
  fi
  print_info_message "→ $script${*:+ ($*)}"
  # Disable errexit around the child so we can record failures.
  set +e
  bash "$DF_SCRIPT_DIR/$script" "$@"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    print_error_message "FAILED ($rc): $script"
    SETUP_FAILURES+=("$script")
    if [[ "$SETUP_CONTINUE_ON_ERROR" != "true" ]]; then
      return "$rc"
    fi
  fi
  return 0
}

# Shared stack
run_setup setup-essentials.sh
run_setup setup-nvidia.sh --yes

if [[ -n "${FULL_NAME:-}" && -n "${EMAIL_ADDRESS:-}" ]]; then
  run_setup setup-git.sh "$FULL_NAME" "$EMAIL_ADDRESS"
else
  print_warning_message "FULL_NAME/EMAIL_ADDRESS not set — skipping setup-git.sh"
fi

run_setup setup-github-cli.sh
run_setup setup-node.sh
run_setup setup-fonts.sh
run_setup setup-bash.sh
run_setup setup-kitty.sh
run_setup setup-cursor.sh
run_setup setup-claude.sh
run_setup setup-herdr.sh
run_setup setup-python.sh
run_setup setup-rust.sh
run_setup setup-golang.sh
run_setup setup-neovim.sh
run_setup setup-tableplus.sh
run_setup setup-docker.sh
run_setup setup-minikube.sh
run_setup setup-code.sh
run_setup setup-php.sh
run_setup setup-ruby.sh
run_setup setup-postman.sh
run_setup setup-moonlander.sh
run_setup setup-spotify.sh
run_setup setup-obsidian.sh

if [[ "$SETUP_PROFILE" == "work" ]]; then
  print_line_break "Work profile — Zoom + Slack + Chrome"
  run_setup setup-zoom.sh
  run_setup setup-slack.sh
  run_setup setup-chrome.sh
else
  print_line_break "Personal profile — Steam + Discord + Firefox + Mullvad"
  run_setup setup-steam.sh
  run_setup setup-discord.sh
  run_setup setup-firefox.sh
  run_setup setup-mullvad.sh
fi

if pacman -Q gnome-shell &>/dev/null; then
  print_info_message "GNOME is installed — running GNOME setup"
  run_setup setup-gnome.sh
else
  print_info_message "GNOME is not installed — skipping GNOME setup"
fi

if [[ ${#SETUP_FAILURES[@]} -gt 0 ]]; then
  print_line_break "Setup finished with failures"
  print_error_message "Failed scripts (${#SETUP_FAILURES[@]}): ${SETUP_FAILURES[*]}"
  print_info_message "Re-run individually, e.g.: bash scripts/${SETUP_FAILURES[0]}"
  exit 1
fi

print_success_message "All setup scripts completed successfully"
exit 0
