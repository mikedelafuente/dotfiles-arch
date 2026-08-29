#!/bin/bash
# Guided pre-install preparation for user_configuration.json.
#
# Run this BEFORE archinstall, from the live ISO (this repo cloned or copied
# to a USB alongside user_configuration.json — see NOTES.md). Prompts for
# the target disk device, hostname, and graphics driver, then writes those
# three fields into user_configuration.json in place.
#
# Does NOT touch user_credentials.json (LUKS/user password) — that stays a
# manual step by design.
#
# Usage:
#   ./prepare-archinstall.sh [--dry-run] [-h]
#
# Options:
#   --dry-run   Print the changes that would be made, without writing
#   -h, --help  Show this help

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Prefer shared helpers when available (GPU-detection functions in fn-lib.sh)
if [ -r "$SCRIPT_DIR/scripts/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/scripts/dotheader.sh"
fi

CONFIG_FILE="$SCRIPT_DIR/user_configuration.json"
DRY_RUN=false

usage() {
  cat <<EOF
Usage: ./prepare-archinstall.sh [--dry-run] [-h]

Interactively prepares user_configuration.json for a fresh archinstall:
  1. Pick the target disk from a live lsblk listing
  2. Enter a hostname
  3. Confirm (or override) a detected graphics driver

Writes the three fields into $CONFIG_FILE in place.
Never touches user_credentials.json — enter the LUKS password yourself.

Options:
  --dry-run   Print the changes that would be made, without writing
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found." >&2
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required to edit $CONFIG_FILE (present by default on the Arch ISO, since archinstall itself needs it)." >&2
  exit 1
fi

if ! command -v lsblk &>/dev/null; then
  echo "Error: lsblk is required to list block devices." >&2
  exit 1
fi

# --------------------------
# 1. Disk selection
# --------------------------

echo ""
echo "Available block devices:"
# -e 7,11 excludes loop and optical devices; zram is excluded separately
# below since lsblk reports it as TYPE=disk too, even though it's RAM-backed
# and not a real wipeable install target.
mapfile -t DISK_LINES < <(lsblk -dpno NAME,SIZE,MODEL -e 7,11 2>/dev/null | grep -v '^/dev/zram')

if ((${#DISK_LINES[@]} == 0)); then
  echo "Error: no block devices found via lsblk." >&2
  exit 1
fi

i=1
for line in "${DISK_LINES[@]}"; do
  printf "  %d) %s\n" "$i" "$line"
  ((i++))
done

read -rp "Select target disk [1-${#DISK_LINES[@]}]: " DISK_CHOICE
if ! [[ "$DISK_CHOICE" =~ ^[0-9]+$ ]] || ((DISK_CHOICE < 1 || DISK_CHOICE > ${#DISK_LINES[@]})); then
  echo "Error: invalid selection." >&2
  exit 1
fi

DISK_DEVICE="$(awk '{print $1}' <<<"${DISK_LINES[$((DISK_CHOICE - 1))]}")"

echo ""
echo "WARNING: archinstall will WIPE $DISK_DEVICE completely."
read -rp "Type the device path again to confirm: " DISK_CONFIRM
if [ "$DISK_CONFIRM" != "$DISK_DEVICE" ]; then
  echo "Error: confirmation did not match — aborting without changes." >&2
  exit 1
fi

# --------------------------
# 2. Hostname
# --------------------------

echo ""
read -rp "Hostname: " HOSTNAME_VALUE
if [ -z "$HOSTNAME_VALUE" ]; then
  echo "Error: hostname cannot be empty." >&2
  exit 1
fi

# --------------------------
# 3. Graphics driver
# --------------------------
# Canonical values (archinstall/lib/hardware.py GfxDriver enum, tag 4.4 —
# see docs/research/archinstall-config-schema.md). Single source of truth:
# every place below indexes into this array rather than retyping the strings.
GFX_DRIVER_OPTIONS=(
  "All open-source"
  "AMD / ATI (open-source)"
  "Intel (open-source)"
  "Nvidia (open kernel module for newer GPUs, Turing+)"
  "Nvidia (open-source nouveau driver)"
  "VirtualBox (open-source)"
)

detect_gfx_driver_index() {
  if declare -F has_nvidia_hardware &>/dev/null && has_nvidia_hardware; then
    echo 3 # Nvidia (open kernel module for newer GPUs, Turing+)
  elif declare -F has_amd_gpu_hardware &>/dev/null && has_amd_gpu_hardware; then
    echo 1 # AMD / ATI (open-source)
  elif declare -F has_intel_gpu_hardware &>/dev/null && has_intel_gpu_hardware; then
    echo 2 # Intel (open-source)
  else
    echo 0 # All open-source
  fi
}

DETECTED_INDEX="$(detect_gfx_driver_index)"
DETECTED_DRIVER="${GFX_DRIVER_OPTIONS[$DETECTED_INDEX]}"

echo ""
echo "Detected graphics driver: $DETECTED_DRIVER"
echo "Options:"
echo "  1) $DETECTED_DRIVER (detected — press Enter to accept)"

# Menu numbers 2+ walk the remaining options in array order (skipping the
# one already offered as the detected default); GFX_MENU_INDEXES maps each
# printed menu number back to its GFX_DRIVER_OPTIONS index.
GFX_MENU_INDEXES=("$DETECTED_INDEX")
menu_number=2
for idx in "${!GFX_DRIVER_OPTIONS[@]}"; do
  [[ "$idx" -eq "$DETECTED_INDEX" ]] && continue
  printf "  %d) %s\n" "$menu_number" "${GFX_DRIVER_OPTIONS[$idx]}"
  GFX_MENU_INDEXES+=("$idx")
  ((menu_number++))
done

read -rp "Choose [1]: " GFX_CHOICE
GFX_CHOICE="${GFX_CHOICE:-1}"
if ! [[ "$GFX_CHOICE" =~ ^[0-9]+$ ]] || ((GFX_CHOICE < 1 || GFX_CHOICE > ${#GFX_MENU_INDEXES[@]})); then
  echo "Error: invalid choice: $GFX_CHOICE" >&2
  exit 1
fi
GFX_DRIVER="${GFX_DRIVER_OPTIONS[${GFX_MENU_INDEXES[$((GFX_CHOICE - 1))]}]}"

# --------------------------
# Apply
# --------------------------

echo ""
echo "Planned changes to $CONFIG_FILE:"
echo "  disk_config.device_modifications[0].device -> $DISK_DEVICE"
echo "  hostname -> $HOSTNAME_VALUE"
echo "  profile_config.gfx_driver -> $GFX_DRIVER"

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "Dry run — no changes written."
  exit 0
fi

python3 - "$CONFIG_FILE" "$DISK_DEVICE" "$HOSTNAME_VALUE" "$GFX_DRIVER" <<'PYEOF'
import json
import sys

config_path, disk_device, hostname, gfx_driver = sys.argv[1:5]

with open(config_path) as f:
    config = json.load(f)

config["disk_config"]["device_modifications"][0]["device"] = disk_device
config["hostname"] = hostname
config["profile_config"]["gfx_driver"] = gfx_driver

with open(config_path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
PYEOF

echo ""
echo "Updated $CONFIG_FILE."
echo "Next: run archinstall with this config (see NOTES.md)."
