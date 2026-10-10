#!/usr/bin/env bash
# Install shared skills and the generated global rule baseline; no OS setup.
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh" >&2
  exit 1
fi
# Use the same rule frontmatter/body readers as workstation rule sync.
# shellcheck source=/dev/null
source "$CURRENT_FILE_DIR/sync-sources-lib.sh"

REPO_ROOT="$(cd "$CURRENT_FILE_DIR/.." && pwd)"
command -v python3 >/dev/null || { print_error_message "python3 is required"; exit 1; }

# The source is an explicit input so a cloud task can consume the standalone
# skills repository.  Reading its data is safe; this installer never sources
# or executes anything from that checkout.
SOURCE_ROOT="$REPO_ROOT"
CLOUD_HOME="$USER_HOME_DIR"
while (($#)); do
  case "$1" in
    --source)
      [[ -n "${2:-}" ]] || { print_error_message "--source requires a directory"; exit 1; }
      SOURCE_ROOT="$2"
      shift 2
      ;;
    --home)
      [[ -n "${2:-}" ]] || { print_error_message "--home requires a directory"; exit 1; }
      CLOUD_HOME="$2"
      shift 2
      ;;
    *)
      print_error_message "Unknown option: $1"
      exit 1
      ;;
  esac
done
baseline="$(mktemp)"
trap 'rm -f "$baseline"' EXIT
shopt -s nullglob
for rule in "$SOURCE_ROOT"/rules/*.md "$SOURCE_ROOT"/rules/*.mdc; do
  [[ "${rule##*/}" != README.md ]] || continue
  always_apply="$(_sync_rule_frontmatter_field "$rule" alwaysApply)"
  [[ "$always_apply" =~ ^true[[:space:]]*$ ]] || continue
  description="$(_sync_rule_frontmatter_field "$rule" description)"
  {
    printf '## %s\n\n' "${description:-${rule##*/}}"
    _sync_rule_body "$rule"
    printf '\n\n'
  } >>"$baseline"
done
python3 "$CURRENT_FILE_DIR/install-cloud-agent-config.py" \
  --source "$SOURCE_ROOT" --home "$CLOUD_HOME" --baseline "$baseline"
