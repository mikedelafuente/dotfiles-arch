#!/bin/bash
# Shared helpers for ~/.local/bin wrappers (dfa-sync-dotfiles, dfa-update-system, dev, zed-agent-init).
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

# Known agent harnesses, in menu / display order. Each id is assumed to also
# be its CLI binary name. Keep in sync by hand with scripts/fn-lib.sh's
# KNOWN_HARNESSES — this copy has to stay sourceable standalone (no
# dotheader.sh/fn-lib.sh) by runtime ~/.local/bin scripts like `dev` and
# `zed-agent-init`.
KNOWN_HARNESSES=(claude codex opencode)

# Echo the installed subset of KNOWN_HARNESSES (one per line, in order).
installed_harnesses() {
  local h
  for h in "${KNOWN_HARNESSES[@]}"; do
    command -v "$h" &>/dev/null && echo "$h"
  done
}

# Resolve the saved DEFAULT_HARNESS (from setup-dev.sh, see fn-lib.sh's
# resolve_default_harness) to the actual CLI binary to run — echoes the
# harness id, or returns 1 if the saved choice is unset/stale (its CLI no
# longer on PATH). Used by both `dev --tmux` and `zed-agent-init`
# so the two stay in sync. Reads the legacy DEFAULT_AGENT key too, for a
# config saved before the DEFAULT_AGENT → DEFAULT_HARNESS rename.
resolve_default_harness_command() {
  local bootstrap_config="$HOME/.config/dotfiles-arch/.dotfiles_bootstrap_config"
  local default_harness="" h

  if [[ -r "$bootstrap_config" ]]; then
    # shellcheck source=/dev/null
    default_harness="$(source "$bootstrap_config" && printf '%s' "${DEFAULT_HARNESS:-${DEFAULT_AGENT:-}}")" 2>/dev/null || default_harness=""
  fi

  for h in "${KNOWN_HARNESSES[@]}"; do
    if [[ "$h" == "$default_harness" ]] && command -v "$h" &>/dev/null; then
      echo "$h"
      return 0
    fi
  done

  return 1
}

# Resolve the default harness like resolve_default_harness_command, but with
# a graceful runtime fallback when the saved choice is stale/unset: silently
# use the sole installed harness, interactively ask when several are
# installed (Enter keeps the first installed one), or return 1 when none are
# installed at all. Session-only — never persists the choice; rerun
# setup-dev.sh to change the saved default. Meant to be called from a real
# terminal (the `dev --tmux` agent pane, a Zed Terminal Thread); falls back to the
# first installed harness without asking when stdin isn't a TTY.
resolve_or_prompt_default_harness() {
  local h
  if h="$(resolve_default_harness_command)"; then
    echo "$h"
    return 0
  fi

  local -a installed=()
  while IFS= read -r h; do
    [[ -n "$h" ]] && installed+=("$h")
  done < <(installed_harnesses)

  if ((${#installed[@]} == 0)); then
    return 1
  fi

  if ((${#installed[@]} == 1)); then
    echo "${installed[0]}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "${installed[0]}"
    return 0
  fi

  {
    echo "The saved default agent harness isn't available. Installed harnesses:"
    local i
    for i in "${!installed[@]}"; do
      printf '  %d) %s\n' "$((i + 1))" "${installed[$i]}"
    done
  } >&2

  local choice
  read -rp "Use which one for this session? (number or name, Enter = ${installed[0]}): " choice
  choice="${choice:-${installed[0]}}"

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#installed[@]})); then
    echo "${installed[$((choice - 1))]}"
    return 0
  fi
  for h in "${installed[@]}"; do
    if [[ "$h" == "${choice,,}" ]]; then
      echo "$h"
      return 0
    fi
  done

  echo "Unrecognized input '$choice'; using ${installed[0]}" >&2
  echo "${installed[0]}"
}

# Find git repositories under a root directory (depth 3, so both
# <root>/project and <root>/owner/project layouts work). Echoes one path per
# line, deduped. Shared by dfa-repos and dfa-update-repos so they can never
# drift on what counts as "a repo under the root".
list_git_repos_under() {
  local root_dir="$1"
  find "$root_dir" -mindepth 1 -maxdepth 3 -type d -name .git -prune -printf '%h\n' 2>/dev/null | sort -u
}

# Derive the tmux session name (and, by extension, the Neovim --listen socket
# name) for a project directory: translate '.', ' ', ':' in the basename to
# '_', falling back to a hash-based name when that leaves nothing usable.
# Shared by `dev --tmux` (session creation) and `nvim-reveal-edit` (socket lookup
# during its upward directory walk) so the mapping can't silently diverge.
tmux_session_name_for() {
  local dir="$1" name
  name="$(basename "$dir" | tr '.' '_' | tr ' ' '_' | tr ':' '_')"
  if [[ -z "$name" || "$name" =~ ^_+$ ]]; then
    name="dev_$(echo "$dir" | md5sum | cut -c1-8)"
  fi
  echo "$name"
}
