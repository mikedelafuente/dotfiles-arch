#!/bin/bash

# --------------------------
# Setup OpenAI Codex CLI for Arch and Ubuntu
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

ensure_harness_cli codex || exit $?

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

python3 "$DF_SCRIPT_DIR/harness-config.py" "$CODEX_CONFIG_TOML" || exit $?

ensure_json_hook_registered "$CODEX_HOOKS_FILE" '{"hooks": {}}' \
  '(.hooks.PostToolUse // []) | any(.hooks[]?.command == "nvim-reveal-edit")' \
  '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher": "apply_patch", "hooks": [{"type": "command", "command": "nvim-reveal-edit", "timeout": 5}]}])' \
  "the Neovim reveal-on-edit PostToolUse hook"

ensure_chatgpt_desktop || exit $?

print_tool_setup_complete "Codex CLI"
