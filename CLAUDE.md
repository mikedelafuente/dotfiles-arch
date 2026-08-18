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
│   ├── .packages.md              # → ../PACKAGES.md (shown by `packages`)
│   └── .local/bin/               # Helpers (code, repos, check-dotfiles, remove-orphans, sync-dotfiles, update-system, …)
├── config/                       # ~/.config application configs
│   ├── fontconfig/fonts.conf
│   ├── nvim/
│   ├── kitty/
│   ├── herdr/
│   ├── bat/config
│   ├── starship.toml
│   └── ...
├── .cursor/rules/                # Repo conventions for AI agents
├── AGENTS.md                     # Short pointer file for agents
├── PACKAGES.md                   # Why each installed package exists
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

Prompts for name, email, **multi-select profiles** (`work`, `personal`, `devcontainer`), **INSTALL_NVIDIA**, and **MACHINE_TYPE** (laptop|desktop; default from `has_battery`), or `--yes` for non-interactive. Then enables multilib, rate-limited guarded package upgrade, installs yay if needed, runs setup scripts, links dotfiles.

### Sync (existing / drifted machine)

```bash
bash scripts/sync.sh
# bash scripts/sync.sh --profile work,devcontainer --yes
```

Always runs a guarded `pacman` + `yay` upgrade (with AUR IoC scan of packages + AUR deps), then setup scripts (unless `--skip-bootstrap`), link, and optional cleanup. Saved profiles/NVIDIA/machine type are kept silently; pass `--prompt` to re-ask. AUR `--noconfirm` only with `--yes`.

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

- `print_*` helpers / `fmt_choice` (turquoise prompt defaults)
- Hardware: `has_nvidia_*`, `has_intel_hardware`, `has_battery`
- Packages: `ensure_pacman_pkgs`, `ensure_yay_installed` (scanned before makepkg), `ensure_yay_pkgs`, `ensure_multilib_enabled`, `safe_system_upgrade`, `remove_orphaned_packages`
- AUR IoC scan: `aur_scan_*` / `aur_scan_package_tree` (fail closed if neither `rg` nor `grep`; known-IoC gate, not full audit)
- NVM: `nvm_dir`, `load_nvm` (`~/.config/nvm`, migrates legacy `~/.nvm`)
- Config: `load_bootstrap_config`, `write_bootstrap_config` (`printf %q`), `validate_bootstrap_profile`, `normalize_setup_profile`, `normalize_setup_profiles`, `has_setup_profile`, `primary_setup_profile`, `resolve_nvidia_preference`, `normalize_machine_type`, `resolve_machine_type`, `machine_is_laptop`
- Cooldown stamps: `record_system_upgrade_stamps`, `system_upgrade_cooldown_expired`
- Fonts: `refresh_font_cache`

### Orchestration

`bootstrap.sh` and `sync.sh` both call:

1. Guarded system upgrade (`safe_system_upgrade`) — sync always; bootstrap when cooldown expired / multilib just enabled
2. `run-profile-setup.sh` — single shared setup-* list; continues on error and prints a failure summary
3. `link-dotfiles.sh`
4. `post-link-hooks.sh` — `fc-cache` after `fonts.conf` is linked; GNOME logout checklist

Config reads/writes go through `load_bootstrap_config` / `write_bootstrap_config` (including `setup-nvidia.sh`).

### Bootstrap config

Stored at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`:

- `FULL_NAME`, `EMAIL_ADDRESS`, `SETUP_PROFILES` (space-separated multi-select),
  `SETUP_PROFILE` (primary for older readers), `INSTALL_NVIDIA`, `MACHINE_TYPE`

`bootstrap.sh` / `sync.sh` export `MACHINE_TYPE` for the setup scripts; `setup-gnome.sh` also falls back to `load_bootstrap_config` + `has_battery`.

### Profiles

Profiles are **additive** — select any combination (e.g. `work,devcontainer`).

| Profile | Extra setup |
|---------|-----------------------------------------------|
| work | Zoom, Slack, Chrome |
| personal | Steam, Discord, Firefox, Mullvad |
| devcontainer | just, mkcert, bind/`dig`, OpenVPN 3 (`openvpn3` AUR), Dev Containers extension, systemd-resolved `~test` DNS, inotify watches |

Shared: Kitty, Herdr, Cursor + Agent CLI, Claude Code, Neovim, languages, Docker, Spotify, Obsidian, GNOME/Pop Shell, etc.

### Special cases

- **setup-git.sh**: Requires name + email args (no TTY → must pass args); writes `~/.config/git/identity` (not the shared `.gitconfig`)
- **setup-node.sh / setup-claude.sh**: NVM at `~/.config/nvm` (checksummed install.sh, never `curl|bash`); Claude uses user-level `npm` (never `sudo npm`)
- **setup-herdr.sh**: AUR `herdr-bin` only (no curl|bash fallback); calls `ensure_yay_installed` if needed
- **setup-gnome.sh**: Only when `gnome-shell` is installed; power policy from `MACHINE_TYPE` (`power-profiles-daemon` profile, `/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf` — laptop suspends on battery lid-close but ignores lid on AC/docked, `90-dotfiles-arch-usb-wakeup.rules` for KVM HID wake, audio powersave), falling back to `has_battery`; installs/configures Dash to Panel (always-visible full-width top bar, small centered icons, every monitor); Pop Shell auto-tiling off by default
- **setup-nvidia.sh**: Installs `nvidia-open-dkms` only when `INSTALL_NVIDIA=true`; never swaps an existing driver flavor; persists via `write_bootstrap_config`
- **setup-fonts.sh**: Adwaita + Noto + Liberation + Nerd Fonts; GNOME UI uses Adwaita Sans / JetBrainsMono NF
- **setup-cursor.sh**: IDE via AUR (`cursor-bin`); Agent CLI via AUR (`cursor-cli`), which ships only `/usr/bin/cursor-agent` — the script adds an `agent` compat symlink and clears any older `curl | bash` install from `~/.local/share/cursor-agent`. On machines with no NVIDIA hardware (integrated-GPU-only; checked via `has_nvidia_hardware` PCI detection, not driver packages), it also drops a `~/.local/share/applications/cursor.desktop` override that adds `--ozone-platform=x11` and idempotently forces `disable-hardware-acceleration: true` in `~/.cursor/argv.json` (JSONC — comments preserved, not a jq rewrite), working around an Electron native-Wayland hang-on-quit/slowness bug; both are removed/left alone automatically if NVIDIA hardware is later detected
- **setup-devcontainer.sh**: Host-only platform devcontainer prerequisites (Docker/`gh`/Cursor already shared)
- **setup-essentials.sh**: `ESSENTIAL_PACKAGES` is the canonical CLI list — update `PACKAGES.md` in the same change
- **`code`**: Creates a Herdr workspace and starts `nvim .` (`--force` skips the git-repo requirement)

## Key design decisions

1. Modular setup scripts for independent re-runs
2. Symlink-based dotfiles (edit in repo, re-link / sync)
3. Rate-limited pacman/yay updates on bootstrap (1-day cooldown); sync always upgrades
4. Portable `$HOME` / `$USER_HOME_DIR` paths for multi-username machines
5. GNOME-first Wayland; Pop Shell for tiling
6. Do not append PATH hacks into the symlinked `~/.bashrc` from setup scripts
7. User-facing commands are documented where the user looks: `home/.welcome.md`, `aliases()`, `PACKAGES.md`, README/REFRESHER

## Important files

- `README.md` / `REFRESHER.md` — human starting point and short memory jogger
- `PACKAGES.md` — why each installed package exists; linked to `~/.packages.md` and shown by `packages`
- `AGENTS.md` + `.cursor/rules/*.mdc` — conventions for AI agents (docs, packages, scripts)
- `scripts/bootstrap.sh` / `scripts/sync.sh` — orchestration
- `scripts/run-profile-setup.sh` / `scripts/post-link-hooks.sh` — shared runner + post-link
- `scripts/update-system.sh` — guarded day-to-day `pacman` + `yay` updater (AUR IoC scan)
- `scripts/fn-lib.sh` — package/nvm/hardware/config/AUR-scan helpers
- `scripts/setup-gnome.sh` — theme, Pop Shell, Dash to Panel, keybindings, GPaste, AppIndicator, No Overview
- `scripts/setup-herdr.sh` — Herdr + Claude/Cursor integrations
- `user_configuration.json` — set disk device and `gfx_driver` per machine
- `NOTES.md` — WiFi, USB config, NVIDIA, sync

## Development notes

- Scripts use bash; prefer `pacman -Q` for install checks
- Run `bash scripts/check.sh` (or `check`) after shell changes — `bash -n` + `shellcheck -x`
- Config persistence: `~/.config/dotfiles-arch/`
- Dotfiles link to `$USER_HOME_DIR`, not root’s home when run with sudo
- Overview at login: `no-overview@fthx` plus optional `hide-gnome-overview` autostart fallback
