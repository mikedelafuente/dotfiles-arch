#!/bin/bash

# --------------------------
# Wire locally-installed Ollama models into Codex + opencode's model lists
# --------------------------
# Must run after setup-codex.sh, setup-opencode.sh, and setup-ollama.sh so
# their binaries/config files exist and `ollama list` reflects what's
# actually been pulled. Idempotent and safe to re-run any time the local
# model set changes (ollama pull/rm) — it fully regenerates the managed
# block/entry each run, so removed models drop out too.
#
# Codex already ships a built-in "ollama" model_provider (localhost:11434),
# so this only needs to add one [profiles."ollama-<model>"] per local model
# (codex --profile "ollama-<model>"). opencode has no built-in local
# provider, so this defines a custom "ollama" provider (openai-compatible)
# listing every local model.

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Harness agent models (Ollama)"

if ! command -v ollama &>/dev/null; then
  print_info_message "ollama not installed — skipping harness model sync"
  print_tool_setup_complete "Harness agent models (Ollama)"
  exit 0
fi

OLLAMA_LIST_OUTPUT=""
if ! OLLAMA_LIST_OUTPUT="$(ollama list 2>/dev/null)"; then
  print_warning_message "ollama is installed but not responding (service not running?) — skipping harness model sync"
  print_tool_setup_complete "Harness agent models (Ollama)"
  exit 0
fi

OLLAMA_MODELS=()
while IFS= read -r name; do
  [[ -n "$name" ]] && OLLAMA_MODELS+=("$name")
done < <(printf '%s\n' "$OLLAMA_LIST_OUTPUT" | tail -n +2 | awk '{print $1}')

if ((${#OLLAMA_MODELS[@]} == 0)); then
  print_info_message "No local Ollama models found — skipping harness model sync"
else
  print_info_message "Local Ollama models: ${OLLAMA_MODELS[*]}"
fi

# --------------------------
# Codex: one profile per model on codex's built-in "ollama" provider
# --------------------------
CODEX_MARKER_BEGIN="# --- dotfiles-arch: ollama model profiles (managed — do not edit by hand) ---"
CODEX_MARKER_END="# --- dotfiles-arch: end ollama model profiles ---"

if command -v codex &>/dev/null; then
  CODEX_CONFIG_TOML="$USER_HOME_DIR/.codex/config.toml"
  mkdir -p "$(dirname "$CODEX_CONFIG_TOML")"
  [ -f "$CODEX_CONFIG_TOML" ] || : > "$CODEX_CONFIG_TOML"

  CODEX_TMP="$(mktemp)"
  awk -v b="$CODEX_MARKER_BEGIN" -v e="$CODEX_MARKER_END" '
    $0==b {skip=1}
    skip!=1 {print}
    $0==e {skip=0}
  ' "$CODEX_CONFIG_TOML" > "$CODEX_TMP"
  # Trim trailing blank lines so re-runs don't grow a gap at EOF.
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$CODEX_TMP"
  mv "$CODEX_TMP" "$CODEX_CONFIG_TOML"

  if ((${#OLLAMA_MODELS[@]} > 0)); then
    {
      echo ""
      echo "$CODEX_MARKER_BEGIN"
      for model in "${OLLAMA_MODELS[@]}"; do
        echo "[profiles.\"ollama-${model}\"]"
        echo "model = \"${model}\""
        echo "model_provider = \"ollama\""
        echo ""
      done
      echo "$CODEX_MARKER_END"
    } >> "$CODEX_CONFIG_TOML"
    print_success_message "Codex: synced ${#OLLAMA_MODELS[@]} local model profile(s) (codex --profile ollama-<model>)"
  else
    print_info_message "Codex: no local models to sync — removed any stale profiles"
  fi
else
  print_info_message "Codex CLI not installed — skipping"
fi

# --------------------------
# opencode: custom "ollama" provider listing every local model
# --------------------------
if command -v opencode &>/dev/null; then
  if ! command -v jq &>/dev/null; then
    print_warning_message "jq not found — skipping opencode model sync"
  else
    OPENCODE_CONFIG="$USER_HOME_DIR/.config/opencode/opencode.jsonc"
    mkdir -p "$(dirname "$OPENCODE_CONFIG")"
    [ -f "$OPENCODE_CONFIG" ] || printf '%s\n' "{\"\$schema\": \"https://opencode.ai/config.json\"}" > "$OPENCODE_CONFIG"

    OPENCODE_TMP="$(mktemp)"
    if ((${#OLLAMA_MODELS[@]} > 0)); then
      MODELS_JSON="$(printf '%s\n' "${OLLAMA_MODELS[@]}" | jq -R . | jq -s 'map({(.): {name: .}}) | add')"
      if jq --argjson models "$MODELS_JSON" \
        '.provider.ollama = {npm: "@ai-sdk/openai-compatible", name: "Ollama (local)", options: {baseURL: "http://localhost:11434/v1"}, models: $models}' \
        "$OPENCODE_CONFIG" > "$OPENCODE_TMP"; then
        mv "$OPENCODE_TMP" "$OPENCODE_CONFIG"
        print_success_message "opencode: synced ${#OLLAMA_MODELS[@]} local model(s) to the \"ollama\" provider"
      else
        rm -f "$OPENCODE_TMP"
        print_warning_message "Could not update $OPENCODE_CONFIG (invalid JSON? comments in .jsonc aren't supported here) — sync it manually"
      fi
    else
      if jq 'del(.provider.ollama)' "$OPENCODE_CONFIG" > "$OPENCODE_TMP"; then
        mv "$OPENCODE_TMP" "$OPENCODE_CONFIG"
      else
        rm -f "$OPENCODE_TMP"
        print_warning_message "Could not update $OPENCODE_CONFIG (invalid JSON? comments in .jsonc aren't supported here) — sync it manually"
      fi
    fi
  fi
else
  print_info_message "opencode not installed — skipping"
fi

print_tool_setup_complete "Harness agent models (Ollama)"
