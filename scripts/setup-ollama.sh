#!/bin/bash

# --------------------------
# Setup Ollama (local model server) for Arch Linux
# --------------------------
# GPU-only: Ollama's CPU-only inference is too slow to be worth installing
# unconditionally, so this script skips entirely unless a working NVIDIA
# driver (nvidia-smi, not just PCI hardware — a card with no driver
# installed has no CUDA to use) or a Vulkan ICD is detected. Installs
# ollama-cuda on NVIDIA, otherwise ollama-vulkan. Never swaps an
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

OLLAMA_FLAVORS=(ollama ollama-cuda ollama-rocm ollama-vulkan)
INSTALLED_FLAVOR=""
for flavor in "${OLLAMA_FLAVORS[@]}"; do
  if pacman -Q "$flavor" &>/dev/null; then
    INSTALLED_FLAVOR="$flavor"
    break
  fi
done

has_nvidia_driver() {
  command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null
}

has_vulkan() {
  [[ -d /usr/share/vulkan/icd.d ]] \
    && find /usr/share/vulkan/icd.d -maxdepth 1 -name "*.json" -print -quit 2>/dev/null | grep -q .
}

if [ -n "$INSTALLED_FLAVOR" ]; then
  print_info_message "Ollama already installed ($INSTALLED_FLAVOR) — leaving flavor alone"
elif has_nvidia_driver; then
  print_info_message "Working NVIDIA driver detected — installing ollama-cuda"
  ensure_pacman_pkgs ollama-cuda
  INSTALLED_FLAVOR="ollama-cuda"
elif has_vulkan; then
  print_info_message "Vulkan ICD detected (no NVIDIA driver) — installing ollama-vulkan"
  ensure_pacman_pkgs ollama-vulkan
  INSTALLED_FLAVOR="ollama-vulkan"
else
  print_info_message "No NVIDIA driver or Vulkan ICD detected — skipping Ollama (CPU-only inference isn't worth installing unconditionally)"
  print_tool_setup_complete "Ollama"
  exit 0
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
