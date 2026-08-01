#!/usr/bin/env bash
# --------------------------
# fn-lib.sh - A library of reusable bash functions for Arch setup scripts
# --------------------------

print_tool_setup_start() {
  local tool_name="$1"
  print_line_break "Starting setup for $tool_name"
}

print_tool_setup_complete() {
  local tool_name="$1"
  print_line_break "Completed setup for $tool_name"
}

# Function to print a green line break with an optional title
print_line_break() {
  local title="$1"
  echo -e "\e[32m--------------------------------------------------\e[0m"
  if [ -n "$title" ]; then
    # get the current time and date and print it along with the title
    local datetime
    datetime=$(date '+%Y-%m-%d %H:%M:%S.%N')
    echo -e "\e[32m$title | $datetime\e[0m"
    echo -e "\e[32m--------------------------------------------------\e[0m"
  fi
}

# Function to print an info message in blue
print_info_message() {
  local message="$1"
  echo -e "\e[34m$message\e[0m"
}   

# Function to print an action message in orange
print_action_message() {
  local message="$1"
  echo -e "\e[38;5;208m$message\e[0m"
}

print_success_message() {
  local message="$1"
  echo -e "\e[32m$message\e[0m"
}

# Function to print a warning message in yellow
print_warning_message() {
  local message="$1"
  echo -e "\e[33m$message\e[0m"
}

# Function to print an error message in red
print_error_message() {
  local message="$1"
  echo -e "\e[31m$message\e[0m"
}

# True when an NVIDIA GPU is visible to the system (PCI).
has_nvidia_hardware() {
  if command -v lspci &>/dev/null; then
    lspci -nn 2>/dev/null | grep -qiE 'NVIDIA.*(VGA|3D|Display)|VGA.*NVIDIA|3D.*NVIDIA|Display.*NVIDIA'
    return $?
  fi
  # Fallback: sysfs vendor ID 10de = NVIDIA
  local vendor
  for vendor in /sys/bus/pci/devices/*/vendor; do
    [[ -r "$vendor" ]] || continue
    if [[ "$(cat "$vendor" 2>/dev/null)" == "0x10de" ]]; then
      return 0
    fi
  done
  return 1
}

# True when Arch NVIDIA driver packages from archinstall / pacman are present.
has_nvidia_packages() {
  pacman -Qq nvidia-open nvidia-open-dkms nvidia nvidia-dkms nvidia-utils 2>/dev/null | grep -q .
}
