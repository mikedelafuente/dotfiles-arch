#!/usr/bin/env bash
# Local lint gate: bash -n + shellcheck on shipped shell scripts.
# Usage: bash scripts/check.sh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

files=()
shopt -s nullglob
for f in scripts/*.sh post_install.sh prepare-archinstall.sh home/.local/bin/*; do
  [[ -f "$f" ]] || continue
  # Skip non-shell helpers if any appear later
  case "$f" in
    *.md|*.txt) continue ;;
  esac
  if head -n1 "$f" | grep -qE '^#!.*(bash|sh)'; then
    files+=("$f")
  elif [[ "$f" == *.sh ]]; then
    files+=("$f")
  fi
done
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No shell scripts found to check" >&2
  exit 1
fi

echo "==> bash -n (${#files[@]} files)"
for f in "${files[@]}"; do
  bash -n "$f"
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck -x"
  shellcheck -x "${files[@]}"
else
  echo "shellcheck not installed — skipped (install via setup-essentials or pacman -S shellcheck)"
fi

echo "OK"
