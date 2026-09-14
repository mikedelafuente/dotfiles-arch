#!/bin/bash
# --------------------------
# Run pending schema migrations
# --------------------------
# Brings a machine from its recorded schema version up to the repo's, running
# each migrations/vN-to-vM-migration.sh in order and stamping after each one.
#
# The stamp lives at ~/.config/dotfiles-arch/.dotfiles_schema_version. Machines
# set up before stamping existed have no file; their version is inferred from
# the dangling symlink each rename left behind (see detect_schema_version_by_landmark).
#
# Usage: bash scripts/migrate.sh [--dry-run] [--rerun-all]
#   --dry-run     Report what would run without running or stamping anything
#   --rerun-all   Re-run every migration from v1, ignoring the recorded version
#
# --yes and --force are accepted and ignored. dfa-daily forwards its own args to
# every step, and a forwarded --force means "bypass the update cooldown" there,
# not "replay every migration" here.

CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

REPO_ROOT="$(cd -- "$CURRENT_FILE_DIR/.." &>/dev/null && pwd)"
DRY_RUN=0
RERUN_ALL=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --rerun-all) RERUN_ALL=1 ;;
    --yes|-y|--force) ;;
    -h|--help)
      sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      print_error_message "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

TARGET_VERSION="$(repo_schema_version)"

if [[ "$RERUN_ALL" -eq 1 ]]; then
  FROM_VERSION=1
  VERSION_SOURCE="--rerun-all (replaying every migration)"
elif [[ -n "$(stored_schema_version)" ]]; then
  FROM_VERSION="$(stored_schema_version)"
  VERSION_SOURCE="recorded in $(schema_version_file)"
else
  FROM_VERSION="$(detect_schema_version_by_landmark)"
  VERSION_SOURCE="inferred from leftover symlinks (no version recorded yet)"
fi

print_line_break "Schema migrations"
print_info_message "Machine is at v$FROM_VERSION — $VERSION_SOURCE"
print_info_message "Repository is at v$TARGET_VERSION"

if ((FROM_VERSION >= TARGET_VERSION)); then
  print_success_message "Already up to date — nothing to migrate"
  # An un-stamped machine that is already current still needs its first stamp.
  if [[ "$DRY_RUN" -eq 0 && -z "$(stored_schema_version)" ]]; then
    write_schema_version "$TARGET_VERSION"
    print_info_message "Recorded v$TARGET_VERSION in $(schema_version_file)"
  fi
  exit 0
fi

applied=0
version="$FROM_VERSION"

while ((version < TARGET_VERSION)); do
  next=$((version + 1))
  migration="$REPO_ROOT/migrations/v${version}-to-v${next}-migration.sh"

  if [ ! -r "$migration" ]; then
    print_error_message "Missing migration: $migration"
    print_info_message "Cannot continue past v$version — stopping here"
    exit 1
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_info_message "Would run: $(basename "$migration")"
    version="$next"
    continue
  fi

  print_action_message "Running $(basename "$migration")"
  if ! bash "$migration"; then
    print_error_message "$(basename "$migration") failed — leaving this machine recorded at v$version"
    exit 1
  fi

  # Stamped per migration, so an interrupted run resumes where it stopped.
  write_schema_version "$next"
  applied=$((applied + 1))
  version="$next"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  print_info_message "Dry run — nothing was run and no version was recorded"
  exit 0
fi

print_line_break "Migrations complete"
print_success_message "Applied $applied migration(s) — now at v$TARGET_VERSION"
print_info_message "Run 'source ~/.bashrc' (or open a new terminal) to pick up any renamed commands."
