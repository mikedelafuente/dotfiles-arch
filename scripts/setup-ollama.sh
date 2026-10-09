#!/bin/bash
# GPU-only Ollama: native Arch flavors, compatible native Ubuntu package if
# available, otherwise verified official archives with a managed user service.
CURRENT_FILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start 'Ollama'
ensure_ollama || exit 1
print_info_message 'GPU inference/model loading remain unverified; no models are downloaded by setup'
print_tool_setup_complete 'Ollama'
