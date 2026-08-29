# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Arch Linux dotfiles and setup automation for a **GNOME (Wayland)** development workstation with Kitty, tmux, Neovim, Cursor, and Claude Code. Profiles distinguish **work** vs **personal** apps; the shared stack is the same on every machine.

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
│   └── .local/bin/               # Helpers (code, zed-agent-init, dfa-repos, dfa-check-dotfiles, dfa-remove-orphans, dfa-sync-dotfiles, dfa-update-system, …)
├── config/                       # ~/.config application configs
│   ├── fontconfig/fonts.conf
│   ├── nvim/
│   ├── kitty/
│   ├── bat/config
│   ├── starship.toml
│   └── ...
├── skills/                       # Personal Claude/Cursor skills (SKILL.md folders)
├── rules/                        # Personal Cursor rules (flat .mdc files)
├── .cursor/rules/                # Repo conventions for AI agents (this repo only — unrelated to rules/)
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
bash scripts/setup-code.sh
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

### `home/.local/bin/` helpers

These scripts (`code`, `zed-agent-init`, `dfa-sync-dotfiles`, `dfa-sync-skills`, `dfa-sync-rules`, `dfa-sync-sources`, `dfa-update-system`, `dfa-repos`, `dfa-update-repos`, `dfa-check-dotfiles`, `dfa-remove-orphans`, `dfa-morning`, …) run from a symlinked `~/.local/bin`, not from inside the repo, so they can't source `dotheader.sh` directly by relative path. Instead they source `dotfiles-arch-lib.sh`, which provides `resolve_dotfiles_arch` (symlink walk-up, then `$DOTFILES_ARCH`, then a list of common clone paths checking for `scripts/sync.sh`) for scripts that need to find the repo root before sourcing anything from `scripts/`, `resolve_default_agent_command` (reads `DEFAULT_AGENT` from the bootstrap config and confirms its CLI is actually on PATH) for `code` and `zed-agent-init` to agree on which agent CLI to start, and `list_git_repos_under` (find git repos under a root directory, depth 3) shared by `dfa-repos` and `dfa-update-repos` so they can't drift on what counts as a repo.

**fn-lib.sh** includes:

- `print_*` helpers / `fmt_choice` (turquoise prompt defaults)
- Hardware: `has_nvidia_*`, `has_intel_hardware`, `has_battery`
- Packages: `ensure_pacman_pkgs`, `ensure_yay_installed` (scanned before makepkg), `ensure_yay_pkgs`, `ensure_multilib_enabled`, `safe_system_upgrade`, `remove_orphaned_packages`
- AUR IoC scan: `aur_scan_*` / `aur_scan_package_tree` (fail closed if neither `rg` nor `grep`; known-IoC gate, not full audit)
- NVM: `nvm_dir`, `load_nvm` (`~/.config/nvm`, migrates legacy `~/.nvm`)
- Config: `load_bootstrap_config`, `write_bootstrap_config` (`printf %q`), `validate_bootstrap_profile`, `normalize_setup_profile`, `normalize_setup_profiles`, `has_setup_profile`, `primary_setup_profile`, `resolve_nvidia_preference`, `normalize_machine_type`, `resolve_machine_type`, `machine_is_laptop`, `resolve_default_agent`
- Cooldown stamps: `record_system_upgrade_stamps`, `system_upgrade_cooldown_expired`
- Fonts: `refresh_font_cache`

### Orchestration

`bootstrap.sh` and `sync.sh` both call:

1. Guarded system upgrade (`safe_system_upgrade`) — sync always; bootstrap when cooldown expired / multilib just enabled
2. `run-profile-setup.sh` — single shared setup-* list; continues on error and prints a failure summary
3. `link-dotfiles.sh`
4. `post-link-hooks.sh` — `fc-cache` after `fonts.conf` is linked; `sync-skills.sh`; `sync-rules.sh`; GNOME logout checklist

Config reads/writes go through `load_bootstrap_config` / `write_bootstrap_config` (including `setup-nvidia.sh`).

### Bootstrap config

Stored at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`:

- `FULL_NAME`, `EMAIL_ADDRESS`, `SETUP_PROFILES` (space-separated multi-select),
  `SETUP_PROFILE` (primary for older readers), `INSTALL_NVIDIA`, `MACHINE_TYPE`,
  `DEFAULT_AGENT` (`cursor`|`claude`, resolved by `setup-code.sh` — see below)

`bootstrap.sh` / `sync.sh` export `MACHINE_TYPE` for the setup scripts; `setup-gnome.sh` also falls back to `load_bootstrap_config` + `has_battery`.

### Profiles

Profiles are **additive** — select any combination (e.g. `work,devcontainer`).

| Profile | Extra setup |
|---------|-----------------------------------------------|
| work | Cursor IDE + Agent CLI, Zoom, Slack, Chrome |
| personal | Steam, Discord, Firefox, Mullvad, opencode |
| devcontainer | just, mkcert, bind/`dig`, OpenVPN 3 (`openvpn3` AUR), Dev Containers extension, systemd-resolved `~test` DNS, inotify watches |

Shared: Kitty, tmux, Claude Code, Neovim, languages, Docker, Spotify, Obsidian, GNOME/Pop Shell, etc. Cursor is work-profile-only (see table above) — `run-profile-setup.sh` runs `setup-code.sh` last so it can detect Cursor when the work profile just installed it.

### Special cases

- **setup-git.sh**: Requires name + email args (no TTY → must pass args); writes `~/.config/git/identity` (not the shared `.gitconfig`)
- **setup-node.sh / setup-claude.sh**: NVM at `~/.config/nvm` (checksummed install.sh, never `curl|bash`); Claude uses user-level `npm` (never `sudo npm`). `setup-claude.sh` also idempotently merges the `nvim-reveal-edit` `PostToolUse` hook into `~/.claude/settings.json` (jq, touching only `.hooks.PostToolUse`)
- **setup-code.sh**: Installs `tmux`, `lazygit`, `lazydocker`; runs last in `run-profile-setup.sh` (after profile extras) so Cursor/Claude are already on PATH; resolves `DEFAULT_AGENT` via `resolve_default_agent` — auto-picks the one CLI installed, prompts (Enter keeps the saved choice) when both are, leaves it empty when neither is — and persists it with `write_bootstrap_config`
- **setup-gnome.sh**: Only when `gnome-shell` is installed; power policy from `MACHINE_TYPE` (`power-profiles-daemon` profile, `/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf` — laptop suspends on battery lid-close but ignores lid on AC/docked, `90-dotfiles-arch-usb-wakeup.rules` for KVM HID wake, audio powersave), falling back to `has_battery`; installs/configures Dash to Panel (always-visible full-width top bar, small centered icons, every monitor); Pop Shell auto-tiling off by default
- **setup-nvidia.sh**: Installs `nvidia-open-dkms` only when `INSTALL_NVIDIA=true`; never swaps an existing driver flavor; persists via `write_bootstrap_config`
- **setup-fonts.sh**: Adwaita + Noto + Liberation + Nerd Fonts; GNOME UI uses Adwaita Sans / JetBrainsMono NF
- **setup-cursor.sh**: work-profile-only (see Profiles table); IDE via AUR (`cursor-bin`); Agent CLI via AUR (`cursor-cli`), which ships only `/usr/bin/cursor-agent` — the script adds an `agent` compat symlink and clears any older `curl | bash` install from `~/.local/share/cursor-agent`. On machines with no NVIDIA hardware (integrated-GPU-only; checked via `has_nvidia_hardware` PCI detection, not driver packages), it also drops a `~/.local/share/applications/cursor.desktop` override that adds `--ozone-platform=x11` and idempotently forces `disable-hardware-acceleration: true` in `~/.cursor/argv.json` (JSONC — comments preserved, not a jq rewrite), working around an Electron native-Wayland hang-on-quit/slowness bug; both are removed/left alone automatically if NVIDIA hardware is later detected. It also idempotently merges the `nvim-reveal-edit` `afterFileEdit` hook into `~/.cursor/hooks.json` (jq, touching only `.hooks.afterFileEdit` — this file is plain JSON, unlike JSONC `argv.json`)
- **setup-devcontainer.sh**: Host-only platform devcontainer prerequisites (Docker/`gh` already shared); the Cursor Dev Containers extension step warns and skips if Cursor isn't installed (i.e. devcontainer profile without work)
- **setup-zed.sh**: Every run (bootstrap/sync) first idempotently removes a stray `~/.local/zed.app` (a manually-installed, self-updating Zed some machines have from before the pacman package existed) and its `~/.local/bin/zed` shim if present — it holds Zed's single-instance lock, so `zed`/`zeditor` can silently be served by that build instead of the pacman-managed one, including a version whose settings schema may not match `config/zed/settings.json`. Then installs `zed` via pacman. Settings are linked to `~/.config/zed/settings.json` via `link-dotfiles.sh` (`config/zed/settings.json`), which sets `agent.terminal_init_command` to `zed-agent-init` (`home/.local/bin/`) — a Zed Terminal Thread (Agent Panel → "+" → Terminal) starts this instead of a hardcoded CLI. `zed-agent-init` calls `resolve_default_agent_command` (`dotfiles-arch-lib.sh`) to exec the same `DEFAULT_AGENT` CLI (`claude` or `cursor-agent`/`agent`) that `code` starts in its agent pane, so picking a default agent in `setup-code.sh` covers both launchers. Unlike `code`'s tmux setup, no `nvim-reveal-edit`-style hook is needed: the agent CLI runs as a Terminal Thread inside the same Zed window as the editor, so Zed's own file watcher already reflects the agent's edits. `config/zed/keymap.json` binds `Ctrl+Alt+T` to `agent::NewTerminalThread` (jumps straight to a Terminal Thread) since Zed has no settings key for which Agent Panel tab opens by default; it's an addition, not an override, so the existing Agent Panel shortcut still opens Zed's native chat
- **sync-skills.sh**: Symlinks each skill folder from dotfiles-arch and any extra sources listed in `~/.config/dotfiles-arch/sync-sources` into `~/.claude/skills/<name>` and `~/.cursor/skills/<name>` (both tools consume the same `SKILL.md` format — Claude Code's own skills scan is not recursive, so each skill is linked individually rather than as one nested folder); later sources override on name collision; prunes managed symlinks when the source is deleted, unlisted, or a skill vanishes upstream. Only ever touches symlinks whose target is a configured source's effective skills dir — real entries elsewhere are never touched. Runs via `post-link-hooks.sh` (so every `bootstrap.sh`/`dfa-sync-dotfiles`) and as a step in `dfa-morning`; also runnable directly as `dfa-sync-skills`. Manage extra sources with `dfa-sync-sources`
- **sync-rules.sh**: Symlinks each `*.mdc` rule file from dotfiles-arch and any extra sources listed in `~/.config/dotfiles-arch/sync-sources` into `~/.cursor/rules/<name>.mdc` (Cursor only — Claude Code has no equivalent auto-loaded rules directory); later sources override on name collision; prunes managed symlinks when the source is deleted, unlisted, or a rule vanishes upstream. Only ever touches symlinks whose target is a configured source's effective rules dir — real entries elsewhere are never touched. Runs via `post-link-hooks.sh` (so every `bootstrap.sh`/`dfa-sync-dotfiles`) and as a step in `dfa-morning`; also runnable directly as `dfa-sync-rules`. Manage extra sources with `dfa-sync-sources`
- **sync-sources.sh**: List/add/remove extra rules/skills sources (`dfa-sync-sources list|add|remove`); dotfiles-arch is always primary. Each source has a type (`dfa-sync-sources add /path --type <type>`): `standard` (default) expects `rules/` and/or `skills/` subdirs under the given path, same layout as dotfiles-arch itself; `skills-root` treats the given path itself as a flat folder of skill dirs (no `skills/` subdir) — for pulling in one subfolder of someone else's skills repo, e.g. `dfa-sync-sources add ~/repos/mattpocock/skills/skills/engineering --type skills-root`; `rules-root` is the same idea for a flat folder of `*.mdc` files. A single upstream repo with several such subfolders (e.g. `mattpocock/skills/skills/{engineering,misc,productivity}`) needs one `--type skills-root` entry per subfolder. Config: `~/.config/dotfiles-arch/sync-sources` (lines are `path` for standard, or `type:path` for other types)
- **setup-essentials.sh**: `ESSENTIAL_PACKAGES` is the canonical CLI list — update `PACKAGES.md` in the same change
- **`code`**: Creates a tmux session (killing/recreating any existing session for the same directory) with a `code` window (`nvim .` left, ~75%) and starts `nvim --listen <socket> .` (`--force` skips the git-repo requirement); `--agent cursor|claude` (default: `DEFAULT_AGENT` from the bootstrap config, falling back to a plain shell if that agent's CLI isn't actually installed) starts that agent CLI in the split pane and focus lands on that pane; `--workspace <name-or-path>` (Cursor only) is forwarded as `cursor-agent --workspace …`; a `lazygit` window is added for git repos when lazygit is installed; a `console` window is always added (plain shell in the project directory). With `--agent claude`, `config/nvim/lua/plugins/claudecode.lua` (`coder/claudecode.nvim`, `provider = "none"`, eager-loaded so its WebSocket/MCP server is up before the agent pane starts) auto-bridges the two: `claude` discovers Neovim via `~/.claude/ide/*.lock` matching cwd, `<leader>as`/`<leader>ab` send a selection/file as context, and Claude can open files/push diffs/read diagnostics through the protocol — `/ide` inside the Claude pane is the manual fallback if it starts before Neovim finishes loading. Separately, for both agents: `nvim-reveal-edit` (`home/.local/bin/`) is registered as a Claude Code `PostToolUse` hook and a Cursor `afterFileEdit` hook (see `setup-claude.sh`/`setup-cursor.sh` below) — it reads the edited file's path from the hook payload, finds the `--listen` socket named after the enclosing `code` session (walking up the file's directory tree), and reveals the file in that Neovim: focuses its window and `:checktime`-reloads it if already open in the current tab, otherwise loads it into the first non-nvim-tree window of that tab — landing like a nvim-tree click rather than a new tab, and never disturbing the tree itself. Silently no-ops outside a `code` session

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
- `scripts/sync-skills.sh` — symlinks `skills/*` from dotfiles-arch + extra repos into `~/.claude/skills` + `~/.cursor/skills`, prunes stale links
- `scripts/sync-rules.sh` — symlinks `rules/*.mdc` from dotfiles-arch + extra repos into `~/.cursor/rules`, prunes stale links
- `scripts/sync-sources.sh` — manage extra rules/skills source repos (`~/.config/dotfiles-arch/sync-sources`)
- `scripts/update-system.sh` — guarded day-to-day `pacman` + `yay` updater (AUR IoC scan)
- `scripts/fn-lib.sh` — package/nvm/hardware/config/AUR-scan helpers
- `scripts/setup-gnome.sh` — theme, Pop Shell, Dash to Panel, keybindings, GPaste, AppIndicator, No Overview
- `scripts/setup-code.sh` — tmux-based `code` launcher + `DEFAULT_AGENT` resolution
- `user_configuration.json` — set disk device and `gfx_driver` per machine
- `NOTES.md` — WiFi, USB config, NVIDIA, sync

## Development notes

- Scripts use bash; prefer `pacman -Q` for install checks
- Run `bash scripts/check.sh` (or `check`) after shell changes — `bash -n` + `shellcheck -x`
- Config persistence: `~/.config/dotfiles-arch/`
- Dotfiles link to `$USER_HOME_DIR`, not root’s home when run with sudo
- Overview at login: `no-overview@fthx` plus optional `hide-gnome-overview` autostart fallback
- Always do work on a branch, never commit directly to `main`
- Once a PR is merged, delete both the local and remote branch and check out `main`

## Agent skills

### Issue tracker

GitHub Issues via the `gh` CLI (repo: `mikedelafuente/dotfiles-arch`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
