# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Arch Linux dotfiles and setup automation for a **GNOME (Wayland)** development workstation with Kitty, Herdr, Neovim, Cursor, and Claude Code. Profiles distinguish **work** vs **personal** apps; the shared stack is the same on every machine.

Includes:

- **Bootstrap / sync**: Orchestrated installers with saved user config
- **Modular `setup-*.sh` scripts**: Per-tool installers
- **Symlinked dotfiles**: `home/` and `config/` linked into `$HOME`
- **archinstall template**: `user_configuration.json` (Btrfs + LUKS + Snapper, GNOME + GDM)

## Repository Structure

```
dotfiles-arch/
├── scripts/
│   ├── bootstrap.sh              # Full new-machine orchestration
│   ├── sync.sh                   # Bring an existing machine up to date
│   ├── run-profile-setup.sh      # Shared setup-* list (bootstrap + sync)
│   ├── post-link-hooks.sh        # After link-dotfiles (fc-cache, GNOME checklist)
│   ├── dotheader.sh              # Common header (SCRIPT_DIR, USER_HOME_DIR)
│   ├── fn-lib.sh                 # Shared helpers (print, packages, nvm, hardware)
│   ├── link-dotfiles.sh          # Symlink home/ + config/ into $HOME
│   └── setup-*.sh                # Individual tool setup scripts
├── home/                         # Dotfiles for ~/
│   ├── .bashrc
│   ├── .gitconfig                # Shared only; includes ~/.config/git/identity
│   └── .local/bin/               # Helpers (code, hide-gnome-overview, sync-dotfiles, update-system, …)
├── config/                       # ~/.config application configs
│   ├── fontconfig/fonts.conf
│   ├── nvim/
│   ├── kitty/
│   ├── herdr/
│   ├── starship.toml
│   └── ...
├── post_install.sh               # Minimal post-archinstall (multilib, NVIDIA?, Kitty)
├── user_configuration.json       # archinstall 4.4 template
└── NOTES.md                      # Install / sync notes
```

## Common Commands

### Bootstrap (new system)

```bash
cd /path/to/dotfiles-arch
bash scripts/bootstrap.sh
```

Prompts for name, email, **work|personal** profile, and **INSTALL_NVIDIA**. Then enables multilib, updates packages, installs yay, runs setup scripts, links dotfiles.

### Sync (existing / drifted machine)

```bash
bash scripts/sync.sh
# bash scripts/sync.sh --profile work|personal --yes
```

### Individual setups

```bash
bash scripts/setup-essentials.sh
bash scripts/setup-neovim.sh
bash scripts/setup-herdr.sh
bash scripts/setup-gnome.sh
bash scripts/setup-git.sh "<full-name>" "<email>"
```

### Link dotfiles

```bash
bash scripts/link-dotfiles.sh [work|personal]
```

Profile argument is recorded for reference; linking is shared. Default profile name: `work`.

## Architecture

### Header + library

Every setup script sources `dotheader.sh` → `fn-lib.sh` and uses `USER_HOME_DIR` (respects `$SUDO_USER`). Do **not** hardcode `/home/<user>` — machines use different usernames.

**fn-lib.sh** includes:

- `print_*` helpers
- Hardware: `has_nvidia_*`, `has_intel_hardware`, `has_battery`
- Packages: `ensure_pacman_pkgs`, `ensure_yay_pkgs`, `remove_orphaned_packages`
- NVM: `nvm_dir`, `load_nvm` (`~/.config/nvm`, migrates legacy `~/.nvm`)
- Config: `load_bootstrap_config`, `validate_bootstrap_profile`, `write_bootstrap_config`
- Fonts: `refresh_font_cache`

### Orchestration

`bootstrap.sh` and `sync.sh` both call:

1. `run-profile-setup.sh` — single shared setup-* list; continues on error and prints a failure summary
2. `link-dotfiles.sh`
3. `post-link-hooks.sh` — `fc-cache` after `fonts.conf` is linked; GNOME logout checklist

### Bootstrap config

Stored at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`:

- `FULL_NAME`, `EMAIL_ADDRESS`, `SETUP_PROFILE`, `INSTALL_NVIDIA`

### Profiles

| Profile   | Extra apps                          |
|-----------|-------------------------------------|
| work      | Zoom, Slack, Chrome                 |
| personal  | Steam, Discord, Firefox, Mullvad    |

Shared: Kitty, Herdr, Cursor + Agent CLI, Claude Code, Neovim, languages, Docker, Spotify, Obsidian, GNOME/Pop Shell, etc.

### Special cases

- **setup-git.sh**: Requires name + email args (no TTY → must pass args); writes `~/.config/git/identity` (not the shared `.gitconfig`)
- **setup-node.sh / setup-claude.sh**: NVM at `~/.config/nvm`; Claude uses user-level `npm` (never `sudo npm`)
- **setup-gnome.sh**: Only when `gnome-shell` is installed; battery detection via power_supply `type`
- **setup-nvidia.sh**: Installs `nvidia-open-dkms` only when `INSTALL_NVIDIA=true`; never swaps an existing driver flavor
- **setup-fonts.sh**: Adwaita + Noto + Liberation + Nerd Fonts; GNOME UI uses Adwaita Sans / JetBrainsMono NF
- **setup-cursor.sh**: IDE via AUR (`cursor-bin`); Agent CLI via AUR (`cursor-cli`), which ships only `/usr/bin/cursor-agent` — the script adds an `agent` compat symlink and clears any older `curl | bash` install from `~/.local/share/cursor-agent`
- **`code`**: Creates a Herdr workspace and starts `nvim .`

## Key design decisions

1. Modular setup scripts for independent re-runs
2. Symlink-based dotfiles (edit in repo, re-link / sync)
3. Rate-limited pacman/yay updates (1-day cooldown)
4. Portable `$HOME` / `$USER_HOME_DIR` paths for multi-username machines
5. GNOME-first Wayland; Pop Shell for tiling
6. Do not append PATH hacks into the symlinked `~/.bashrc` from setup scripts

## Important files

- `README.md` / `REFRESHER.md` — human starting point and short memory jogger
- `scripts/bootstrap.sh` / `scripts/sync.sh` — orchestration
- `scripts/run-profile-setup.sh` / `scripts/post-link-hooks.sh` — shared runner + post-link
- `scripts/update-system.sh` — guarded day-to-day `pacman` + `yay` updater (AUR IoC scan)
- `scripts/fn-lib.sh` — package/nvm/hardware/config/AUR-scan helpers
- `scripts/setup-gnome.sh` — theme, Pop Shell, keybindings, GPaste, AppIndicator, No Overview
- `scripts/setup-herdr.sh` — Herdr + Claude/Cursor integrations
- `user_configuration.json` — set disk device and `gfx_driver` per machine
- `NOTES.md` — WiFi, USB config, NVIDIA, sync

## Development notes

- Scripts use bash; prefer `pacman -Q` for install checks
- Config persistence: `~/.config/dotfiles-arch/`
- Dotfiles link to `$USER_HOME_DIR`, not root’s home when run with sudo
- Overview at login: `no-overview@fthx` plus optional `hide-gnome-overview` autostart fallback
