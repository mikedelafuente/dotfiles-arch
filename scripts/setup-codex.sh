#!/bin/bash

# --------------------------
# Setup OpenAI Codex CLI for Arch Linux
# --------------------------

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Codex CLI"

# Prefer user-level NVM npm (never sudo npm — mixes root globals with NVM).
if ! load_nvm || ! command -v npm &>/dev/null; then
  print_error_message "npm not found. Run setup-node.sh first (NVM at ~/.config/nvm)."
  exit 1
fi

if command -v codex &>/dev/null; then
  print_info_message "Codex CLI is already installed: $(command -v codex)"
else
  print_action_message "Installing Codex CLI via user npm (no sudo)"
  npm install -g @openai/codex
fi

if command -v codex &>/dev/null; then
  print_success_message "Codex CLI available as: $(command -v codex)"
  codex --version 2>/dev/null || true
else
  print_error_message "Codex CLI installation may have failed"
  exit 1
fi

# --------------------------
# PostToolUse hook: reveal edited files in the paired Neovim pane
# --------------------------
# Codex's hook system is experimental and disabled by default — enable it,
# then idempotently ensure nvim-reveal-edit runs after apply_patch (Codex's
# canonical tool_name for every file edit, covering the Edit/Write matcher
# aliases too). Only touches .hooks.PostToolUse / [features] so any other
# configured hooks/features are left alone.
CODEX_CONFIG_DIR="$USER_HOME_DIR/.codex"
CODEX_CONFIG_TOML="$CODEX_CONFIG_DIR/config.toml"
CODEX_HOOKS_FILE="$CODEX_CONFIG_DIR/hooks.json"

mkdir -p "$CODEX_CONFIG_DIR"
[ -f "$CODEX_CONFIG_TOML" ] || : > "$CODEX_CONFIG_TOML"

if grep -qE '^\s*codex_hooks\s*=\s*true\b' "$CODEX_CONFIG_TOML" 2>/dev/null; then
  : # already enabled
elif grep -q '^\[features\]' "$CODEX_CONFIG_TOML" 2>/dev/null; then
  sed -i '/^\[features\]/a codex_hooks = true' "$CODEX_CONFIG_TOML"
  print_success_message "Enabled codex_hooks in $CODEX_CONFIG_TOML"
else
  {
    echo ""
    echo "[features]"
    echo "codex_hooks = true"
  } >> "$CODEX_CONFIG_TOML"
  print_success_message "Enabled codex_hooks in $CODEX_CONFIG_TOML"
fi

ensure_json_hook_registered "$CODEX_HOOKS_FILE" '{"hooks": {}}' \
  '(.hooks.PostToolUse // []) | any(.hooks[]?.command == "nvim-reveal-edit")' \
  '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher": "apply_patch", "hooks": [{"type": "command", "command": "nvim-reveal-edit", "timeout": 5}]}])' \
  "the Neovim reveal-on-edit PostToolUse hook"

print_tool_setup_complete "Codex CLI"
