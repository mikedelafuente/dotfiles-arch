#!/bin/bash
# Shared helpers for ~/.local/bin wrappers (sync-dotfiles, update-system, code, zed-agent-init).
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

# Resolve the saved DEFAULT_AGENT (from setup-code.sh, see fn-lib.sh's
# resolve_default_agent) to the actual CLI binary to run — echoes "claude",
# "cursor-agent", or "agent" (cursor-cli's compat shim), or returns 1 if the
# saved choice is unset/stale (its CLI no longer on PATH). Used by both
# `code` (no --agent flag) and `zed-agent-init` so the two stay in sync.
resolve_default_agent_command() {
  local bootstrap_config="$HOME/.config/dotfiles-arch/.dotfiles_bootstrap_config"
  local default_agent=""

  if [[ -r "$bootstrap_config" ]]; then
    # shellcheck source=/dev/null
    default_agent="$(source "$bootstrap_config" && printf '%s' "${DEFAULT_AGENT:-}")" 2>/dev/null || default_agent=""
  fi

  case "$default_agent" in
    cursor)
      if command -v cursor-agent &>/dev/null; then
        echo "cursor-agent"
        return 0
      elif command -v agent &>/dev/null; then
        echo "agent"
        return 0
      fi
      ;;
    claude)
      if command -v claude &>/dev/null; then
        echo "claude"
        return 0
      fi
      ;;
  esac

  return 1
}
