#!/bin/bash
# --------------------------
# Shared profile setup runner
# --------------------------
# Used by bootstrap.sh and sync.sh so the script list cannot drift.
#
# Required env:
#   SETUP_PROFILES   space-separated multi-select: work personal devcontainer
#                    (legacy SETUP_PROFILE=work|personal still accepted via migrate)
# Optional env:
#   FULL_NAME / EMAIL_ADDRESS   (skips setup-git.sh if either missing)
#   MACHINE_TYPE                laptop|desktop — power policy in setup-gnome.sh
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

migrate_setup_profiles_from_legacy
if ! validate_bootstrap_profile; then
  print_error_message "SETUP_PROFILES must include work, personal, and/or devcontainer (got: ${SETUP_PROFILES:-unset})"
  exit 1
fi

print_line_break "Profile setup: $(format_setup_profiles)"

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
run_setup setup-claude.sh
run_setup setup-python.sh
run_setup setup-rust.sh
run_setup setup-golang.sh
run_setup setup-neovim.sh
run_setup setup-tableplus.sh
run_setup setup-docker.sh
run_setup setup-minikube.sh
run_setup setup-php.sh
run_setup setup-ruby.sh
run_setup setup-postman.sh
run_setup setup-moonlander.sh
run_setup setup-spotify.sh
run_setup setup-obsidian.sh
run_setup setup-voxtype.sh
run_setup setup-zed.sh

# Additive profile extras (multi-select — all selected profiles are installed)
if has_setup_profile work; then
  print_line_break "Work profile — Cursor + Zoom + Slack + Chrome"
  run_setup setup-cursor.sh
  run_setup setup-zoom.sh
  run_setup setup-slack.sh
  run_setup setup-chrome.sh
fi

if has_setup_profile personal; then
  print_line_break "Personal profile — Steam + Discord + Firefox + Mullvad + opencode"
  run_setup setup-steam.sh
  run_setup setup-discord.sh
  run_setup setup-firefox.sh
  run_setup setup-mullvad.sh
  run_setup setup-opencode.sh
fi

if has_setup_profile devcontainer; then
  print_line_break "Devcontainer profile — host prerequisites for platform sandbox"
  run_setup setup-devcontainer.sh
fi

# Runs after profile extras so it can detect Cursor when the work profile just installed it.
run_setup setup-code.sh

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
