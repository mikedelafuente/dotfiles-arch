#!/bin/bash

# --------------------------
# Setup Docker for Arch Linux
# --------------------------

# --------------------------
# Import Common Header 
# --------------------------

# add header file
CURRENT_FILE_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)"

# source header (uses SCRIPT_DIR and loads lib.sh)
if [ -r "$CURRENT_FILE_DIR/dotheader.sh" ]; then
  # shellcheck source=/dev/null
  source "$CURRENT_FILE_DIR/dotheader.sh"
else
  echo "Missing header file: $CURRENT_FILE_DIR/dotheader.sh"
  exit 1
fi

# --------------------------
# End Import Common Header 
# --------------------------

print_tool_setup_start "Docker"

# --------------------------
# Check if Docker is Already Installed
# --------------------------

# Check to see if Docker is already installed and working
if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
  print_info_message "Docker is already installed and working."

  # Ensure user is in docker group
  if [ -n "${SUDO_USER-}" ]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="$USER"
  fi

  if ! groups "$TARGET_USER" | grep -q docker; then
    print_info_message "Adding user '$TARGET_USER' to docker group"
    sudo usermod -aG docker "$TARGET_USER"
    print_warning_message "You need to log out and log back in for group changes to take effect"
  fi

  print_tool_setup_complete "Docker"
  exit 0
fi

# --------------------------
# Remove Old Docker Versions (Only if Installing)
# --------------------------

# Uninstall old incompatible packages if they exist
OLD_PACKAGES=()
for pkg in docker-compose podman podman-docker; do
  if pacman -Q "$pkg" &> /dev/null; then
    OLD_PACKAGES+=("$pkg")
  fi
done

if [ ${#OLD_PACKAGES[@]} -gt 0 ]; then
  print_info_message "Removing old/conflicting packages: ${OLD_PACKAGES[*]}"
  sudo pacman -R --noconfirm "${OLD_PACKAGES[@]}"
fi

# --------------------------
# Install Docker Packages
# --------------------------

# Install Docker Engine and related packages from official Arch repos
print_info_message "Installing Docker Engine, CLI, and plugins"
sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
# --------------------------
# Configure and Start Docker Service
# --------------------------

# Start and enable Docker service
print_info_message "Starting and enabling Docker service"
sudo systemctl start docker
sudo systemctl enable --now docker

# --------------------------
# Add User to Docker Group
# --------------------------

# Add original user (when run with sudo) or current user to the docker group
if [ -n "${SUDO_USER-}" ]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$USER"
fi

print_info_message "Adding user '$TARGET_USER' to docker group"
sudo usermod -aG docker "$TARGET_USER"

# --------------------------
# Install Lazy Docker
# --------------------------

if ! command -v lazydocker &> /dev/null; then
    print_info_message "Installing lazydocker from official repos"
    sudo pacman -S --needed --noconfirm lazydocker
else
    print_info_message "lazydocker is already installed. Skipping installation."
fi


# --------------------------
# Installation Complete
# --------------------------

echo ""
print_info_message "Docker installation completed successfully!"
docker --version
echo ""
print_warning_message "IMPORTANT: To apply the new group membership, please log out and log back in,"
print_warning_message "or restart your terminal session. You may also need to restart your system."
echo ""

print_tool_setup_complete "Docker"

