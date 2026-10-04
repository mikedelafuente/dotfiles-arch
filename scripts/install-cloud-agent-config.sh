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
baseline="$(mktemp)"
trap 'rm -f "$baseline"' EXIT
shopt -s nullglob
for rule in "$REPO_ROOT"/rules/*.md "$REPO_ROOT"/rules/*.mdc; do
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
  --source "$REPO_ROOT" --home "$USER_HOME_DIR" --baseline "$baseline" "$@"
