#!/bin/bash

# --------------------------
# Setup Claude Code CLI for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Claude Code"

# Prefer user-level NVM npm (never sudo npm — mixes root globals with NVM).
if ! load_nvm || ! command -v npm &>/dev/null; then
  print_error_message "npm not found. Run setup-node.sh first (NVM at ~/.config/nvm)."
  exit 1
fi

if command -v claude &>/dev/null; then
  print_info_message "Claude Code is already installed: $(command -v claude)"
else
  print_action_message "Installing Claude Code via user npm (no sudo)"
  npm install -g @anthropic-ai/claude-code
fi

if command -v claude &>/dev/null; then
  print_success_message "Claude Code available as: $(command -v claude)"
  claude --version 2>/dev/null || true
else
  print_error_message "Claude Code installation may have failed"
  exit 1
fi

# --------------------------
# PostToolUse hook: reveal edited files in the paired Neovim pane
# --------------------------
# Idempotently ensures nvim-reveal-edit runs after Edit/Write/NotebookEdit.
# Only touches .hooks.PostToolUse so any existing hooks (e.g. SessionStart)
# are left alone.
CLAUDE_SETTINGS_FILE="$USER_HOME_DIR/.claude/settings.json"

ensure_claude_nvim_reveal_hook() {
  if ! command -v jq &>/dev/null; then
    print_warning_message "jq not found — skipping Neovim reveal-on-edit hook for Claude Code"
    return
  fi

  mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
  [ -f "$CLAUDE_SETTINGS_FILE" ] || echo '{}' > "$CLAUDE_SETTINGS_FILE"

  if jq -e '(.hooks.PostToolUse // []) | any(.hooks[]?.command == "nvim-reveal-edit")' \
    "$CLAUDE_SETTINGS_FILE" &>/dev/null; then
    return
  fi

  local tmp
  tmp="$(mktemp)"
  if jq '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher": "Edit|Write|NotebookEdit", "hooks": [{"type": "command", "command": "nvim-reveal-edit", "timeout": 5}]}])' \
    "$CLAUDE_SETTINGS_FILE" > "$tmp"; then
    mv "$tmp" "$CLAUDE_SETTINGS_FILE"
    print_success_message "Added Neovim reveal-on-edit hook to $CLAUDE_SETTINGS_FILE"
  else
    rm -f "$tmp"
    print_warning_message "Could not update $CLAUDE_SETTINGS_FILE — add the PostToolUse hook manually"
  fi
}

ensure_claude_nvim_reveal_hook

print_tool_setup_complete "Claude Code"
