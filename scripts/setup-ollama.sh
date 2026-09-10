#!/bin/bash

# --------------------------
# Setup Ollama (local model server) for Arch Linux
# --------------------------
# Installs the CPU-only ollama package by default, or ollama-cuda when a
# working NVIDIA driver is present (nvidia-smi, not just PCI hardware — a
# card with no driver installed has no CUDA to use). Never swaps an
# already-installed flavor; enables/starts the systemd service either way.

CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

print_tool_setup_start "Ollama"

OLLAMA_FLAVORS=(ollama ollama-cuda ollama-rocm)
INSTALLED_FLAVOR=""
for flavor in "${OLLAMA_FLAVORS[@]}"; do
  if pacman -Q "$flavor" &>/dev/null; then
    INSTALLED_FLAVOR="$flavor"
    break
  fi
done

if [ -n "$INSTALLED_FLAVOR" ]; then
  print_info_message "Ollama already installed ($INSTALLED_FLAVOR) — leaving flavor alone"
elif command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
  print_info_message "Working NVIDIA driver detected — installing ollama-cuda"
  ensure_pacman_pkgs ollama-cuda
  INSTALLED_FLAVOR="ollama-cuda"
else
  print_info_message "No working NVIDIA driver detected — installing CPU-only ollama"
  ensure_pacman_pkgs ollama
  INSTALLED_FLAVOR="ollama"
fi

if command -v ollama &>/dev/null; then
  print_success_message "Ollama available as: $(command -v ollama) ($INSTALLED_FLAVOR)"
else
  print_error_message "Ollama installation may have failed"
  exit 1
fi

print_action_message "Enabling and starting the ollama systemd service"
if sudo systemctl enable --now ollama &>/dev/null; then
  print_success_message "ollama.service enabled and running"
else
  print_warning_message "Could not enable/start ollama.service — run: sudo systemctl enable --now ollama"
fi

print_tool_setup_complete "Ollama"
