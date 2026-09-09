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

# docker_target_user / docker_ensure_ready are shared by both the catalog
# dispatch below and the direct-invocation flow further down, so there is
# exactly one place that decides who to add to the docker group and how.
docker_target_user() {
  if [ -n "${SUDO_USER-}" ]; then
    echo "$SUDO_USER"
  else
    echo "$USER"
  fi
}

# Enables/starts the docker service and adds the target user to the docker
# group if not already a member. Idempotent — safe to call every run.
docker_ensure_ready() {
  sudo systemctl enable --now docker
  local target_user
  target_user="$(docker_target_user)"
  if ! groups "$target_user" | grep -q docker; then
    print_info_message "Adding user '$target_user' to docker group"
    sudo usermod -aG docker "$target_user"
    print_warning_message "You need to log out and log back in for group changes to take effect"
  fi
}

# --install / --uninstall <packages...>
#   The dfa Catalog Engine's System Adapter path — the "docker" catalog item
#   (dfa/catalog/items/docker.toml). Installs/removes exactly the given
#   pacman packages via the shared ensure_pacman_pkgs/remove_pacman_pkgs
#   helpers; --install also brings the service/group up (skipped if the
#   package install failed) so a dfa-driven install is actually usable, not
#   just packages on disk.
case "${1:-}" in
  --install)
    shift
    ensure_pacman_pkgs "$@"
    status=$?
    if [ "$status" -eq 0 ] && command -v docker >/dev/null 2>&1; then
      docker_ensure_ready
    fi
    exit $status
    ;;
  --uninstall)
    shift
    target_user="$(docker_target_user)"
    if groups "$target_user" | grep -q docker; then
      print_info_message "Removing user '$target_user' from docker group"
      sudo gpasswd -d "$target_user" docker >/dev/null 2>&1 || true
    fi
    if command -v docker >/dev/null 2>&1; then
      sudo systemctl disable --now docker >/dev/null 2>&1 || true
    fi
    remove_pacman_pkgs "$@"
    exit $?
    ;;
esac

print_tool_setup_start "Docker"

# --------------------------
# Check if Docker is Already Installed
# --------------------------

# Check to see if Docker is already installed and working
if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
  print_info_message "Docker is already installed and working."
  docker_ensure_ready

  print_tool_setup_complete "Docker"
  exit 0
fi

# --------------------------
# Remove Old Docker Versions (Only if Installing)
# --------------------------

# Uninstall old incompatible packages if they exist
remove_pacman_pkgs docker-compose podman podman-docker

# --------------------------
# Install Docker Packages
# --------------------------

# Install Docker Engine and related packages from official Arch repos
print_info_message "Installing Docker Engine, CLI, and plugins"
sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx
# --------------------------
# Configure and Start Docker Service, Add User to Group
# --------------------------

docker_ensure_ready

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

