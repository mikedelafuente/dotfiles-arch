#!/bin/bash
# Shared helpers for ~/.local/bin wrappers (sync-dotfiles, update-system).
# Sourced by those scripts — not meant to be executed directly.

# Resolve the dotfiles-arch repo root. Prefers symlink walk-up, then DOTFILES_ARCH, then candidates.
resolve_dotfiles_arch() {
  local d candidates=() self

  # If this file (or the caller) is a symlink into the repo, walk up from the real path first
  self="$(readlink -f "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" 2>/dev/null || realpath "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" 2>/dev/null || echo "")"
  if [[ -n "$self" ]]; then
    candidates+=("$(cd "$(dirname "$self")/../../.." && pwd)")
  fi

  if [[ -n "${DOTFILES_ARCH:-}" ]]; then
    candidates+=("$DOTFILES_ARCH")
  fi
  candidates+=(
    "$HOME/repos/dotfiles-arch"
    "$HOME/repos/mikedelafuente/dotfiles-arch"
    "$HOME/dotfiles-arch"
    "$HOME/src/dotfiles-arch"
  )

  for d in "${candidates[@]}"; do
    if [[ -f "$d/scripts/sync.sh" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}
