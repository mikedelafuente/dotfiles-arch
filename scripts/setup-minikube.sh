#!/bin/bash

# --------------------------
# Setup Minikube for Arch Linux
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

print_tool_setup_start "Minikube"

# --------------------------
# Check if Minikube is Already Installed
# --------------------------

# Check to see if Minikube is already installed and working
if command -v minikube >/dev/null 2>&1 && minikube version >/dev/null 2>&1; then
  print_info_message "Minikube is already installed and working."
  minikube version

  # Check if kubectl is also installed
  if ! command -v kubectl >/dev/null 2>&1; then
    print_info_message "kubectl is not installed. Installing kubectl..."
    sudo pacman -S --needed --noconfirm kubectl
  else
    print_info_message "kubectl is already installed."
  fi

  # Check if k9s is also installed
  if ! command -v k9s >/dev/null 2>&1; then
    print_info_message "k9s is not installed. Installing k9s..."
    sudo pacman -S --needed --noconfirm k9s
  else
    print_info_message "k9s is already installed."
  fi

  print_tool_setup_complete "Minikube"
  exit 0
fi

# --------------------------
# Install Minikube and kubectl
# --------------------------

# Install Minikube from official Arch repos
print_info_message "Installing Minikube"
sudo pacman -S --needed --noconfirm minikube

# Install kubectl (Kubernetes CLI) if not already installed
if ! command -v kubectl >/dev/null 2>&1; then
  print_info_message "Installing kubectl"
  sudo pacman -S --needed --noconfirm kubectl
else
  print_info_message "kubectl is already installed."
fi

# Install k9s (Kubernetes terminal UI) if not already installed
if ! command -v k9s >/dev/null 2>&1; then
  print_info_message "Installing k9s"
  sudo pacman -S --needed --noconfirm k9s
else
  print_info_message "k9s is already installed."
fi

# --------------------------
# Verify Installation
# --------------------------

print_info_message "Verifying Minikube installation"
minikube version
echo ""

print_info_message "Verifying kubectl installation"
kubectl version --client
echo ""

print_info_message "Verifying k9s installation"
k9s version
echo ""

# --------------------------
# Installation Complete
# --------------------------

echo ""
print_info_message "Minikube installation completed successfully!"
echo ""
print_info_message "To start using Minikube:"
print_info_message "  1. Start Minikube: minikube start"
print_info_message "  2. Check status: minikube status"
print_info_message "  3. Access dashboard: minikube dashboard"
print_info_message "  4. Manage cluster with k9s: k9s"
print_info_message "  5. Stop Minikube: minikube stop"
echo ""
print_info_message "Minikube will use Docker as the default driver if available."
print_info_message "You can specify a different driver with: minikube start --driver=<driver>"
echo ""

print_tool_setup_complete "Minikube"
