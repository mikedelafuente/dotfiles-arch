# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Arch Linux dotfiles and configuration repository that automates system setup for a development workstation with Hyprland (Wayland compositor), GNOME, and developer tools. The project includes:

- **Bootstrap System**: Automated setup orchestration with user configuration
- **Individual Setup Scripts**: Modular installers for specific tools and applications
- **Dotfiles Linking**: Symlink management for configuration files
- **User Configurations**: Pre-configured settings for Arch installation and development environments

## Repository Structure

```
dotfiles-arch/
├── scripts/
│   ├── bootstrap.sh              # Main orchestration script (entry point)
│   ├── dotheader.sh              # Common header sourced by all scripts
│   ├── fn-lib.sh                 # Shared utility functions
│   ├── link-dotfiles.sh          # Symlink dotfiles to home directory
│   ├── setup-*.sh                # Individual tool setup scripts
│   └── ...
├── home/                          # Dotfiles for home directory (~/)
│   ├── .bashrc                   # Bash configuration
│   ├── .gitconfig                # Git configuration
│   ├── .tmux.conf                # Tmux configuration
│   └── ...
├── config/                        # Application config directories
│   ├── nvim/                     # Neovim configuration (LazyVim)
│   ├── kitty/                    # Kitty terminal config
│   ├── hypr/                     # Hyprland config
│   ├── alacritty/                # Alacritty terminal config
│   └── ...
├── post_install.sh               # Minimal post-installation script
├── user_configuration.json       # Archinstall configuration template
└── NOTES.md                      # Installation notes
```

## Common Commands

### Bootstrap New System

The primary entry point for setting up a new Arch Linux system:

```bash
cd /path/to/dotfiles-arch
bash scripts/bootstrap.sh
```

This script:
1. Collects user information (full name, email)
2. Enables multilib in pacman
3. Updates system packages and installs yay (AUR helper)
4. Sequentially runs all setup-*.sh scripts
5. Links dotfiles to home directory
6. Cleans up orphaned packages

### Run Individual Setup Scripts

Each setup script can be run independently (useful for debugging or re-running specific installations):

```bash
bash scripts/setup-essentials.sh
bash scripts/setup-neovim.sh
bash scripts/setup-rust.sh
bash scripts/setup-docker.sh
bash scripts/setup-git.sh <full-name> <email-address>
```

### Link Dotfiles

Create symbolic links from the repository's dotfiles to the home directory:

```bash
bash scripts/link-dotfiles.sh [profile-name]
```

The profile name defaults to "dela" if not specified.

## Architecture & Design Patterns

### Sourced Header and Library System

All setup scripts follow a consistent pattern:
1. Source `dotheader.sh` which sets up the script directory and loads `fn-lib.sh`
2. Use utility functions from `fn-lib.sh` for consistent output formatting

**fn-lib.sh utilities** (scripts/fn-lib.sh):
- `print_line_break()` - Prints green section headers with timestamp
- `print_info_message()` - Blue information messages
- `print_action_message()` - Orange action messages
- `print_success_message()` - Green success messages
- `print_warning_message()` - Yellow warning messages
- `print_error_message()` - Red error messages
- `print_tool_setup_start()` / `print_tool_setup_complete()` - Tool-specific wrappers

### Bootstrap Configuration

The bootstrap process:
- Stores configuration at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`
- Caches timestamps for package manager updates to avoid redundant operations
- Conditionally runs setup scripts based on what's already installed (uses `pacman -Q`)
- Handles sudo context properly (distinguishes between real user and sudo user)

### Setup Script Conventions

Each `setup-*.sh` script:
- Sources dotheader.sh for utilities and proper script directory detection
- Checks if the tool is already installed before installing
- Handles both official pacman packages and AUR packages
- Uses consistent output formatting

### Special Cases

**setup-git.sh**: Accepts full name and email as arguments (passed from bootstrap.sh)

**setup-gnome.sh** and **setup-hyprland.sh**: Only run if those desktop environments are installed

**Rust Installation** (setup-rust.sh): Uses rustup instead of pacman package for better flexibility with multiple toolchain versions

## Key Design Decisions

1. **Modular Setup Scripts**: Each tool has its own script for clarity and independent execution
2. **Conditional Execution**: Bootstrap only runs scripts if the tool isn't already installed
3. **Rate-Limited Updates**: Package manager updates are cached (1-day cooldown) to avoid redundant operations
4. **Symlink-Based Dotfiles**: Configuration files are linked, not copied, allowing easy updates
5. **Single-User Focus**: Designed for user-level setup, not system-wide deployments
6. **Wayland-First**: Configured for Hyprland with GNOME as fallback

## Important Files

- **scripts/dotheader.sh**: Sets up `SCRIPT_DIR` variable and sources `fn-lib.sh` - required by all setup scripts
- **scripts/fn-lib.sh**: Contains all utility functions for consistent formatting and output
- **scripts/bootstrap.sh**: Orchestration logic and sequencing of all setup operations
- **user_configuration.json**: Template for Archinstall - customize disk config, hostname, and auth before use
- **post_install.sh**: Minimal fallback setup (enables multilib and installs NVIDIA drivers and hyprland)

## Development Notes

- All scripts assume bash (`#!/bin/bash`)
- Scripts use `-e` flags where appropriate to fail on errors
- Configuration is stored in `~/.config/dotfiles-arch/` for persistence across runs
- The bootstrap script checks `$SUDO_USER` to handle being run with sudo
- Package checks use `pacman -Q` to detect installed packages (returns error if not found)
- Dotfiles are symlinked to `$HOME`, derived from `$SUDO_USER` when running with sudo
