# dotfiles-arch

Arch Linux workstation setup for a **GNOME (Wayland)** development machine: Kitty, tmux, Neovim, Cursor, Claude Code, and a modular bootstrap/sync system.

This README is the starting point. Detailed install notes live in [NOTES.md](NOTES.md). After a long break, use [REFRESHER.md](REFRESHER.md).

---

## Choose your path

| Situation | What to run |
|-----------|-------------|
| **Brand-new Arch install** | archinstall → `./post_install.sh` → `bash scripts/bootstrap.sh` |
| **Existing machine / other PC** | `bash scripts/sync.sh` |
| **Day-to-day package updates** | `bash scripts/update-system.sh` (guarded `pacman` + `yay`) |
| **Just re-link configs** | `bash scripts/link-dotfiles.sh` |
| **One tool only** | `bash scripts/setup-<tool>.sh` |

Paths use `$HOME` — different usernames on other machines are fine.

### Day-to-day updates (preferred)

```bash
morning                       # update-repos + update-system (edit ~/.local/bin/morning to customize)
update-system                 # after link-dotfiles; or:
bash scripts/update-system.sh
bash scripts/update-system.sh --yes        # non-interactive after clean AUR scan
bash scripts/update-system.sh --scan-only  # scan pending AUR upgrades only
update-repos                  # parallel git pull --ff-only under ~/repos (MAX_PARALLEL=8)
```

This is the guarded replacement for raw `yay -Syu`: official repos via pacman, then AUR PKGBUILD IoC scan, then yay. Sync always runs the same upgrade path; bootstrap uses it behind a 1-day cooldown. Both use the same scan before any `--noconfirm` AUR install.

---

## New install

### 1. Install Arch (archinstall)

Target schema matches **archinstall 4.4** (`user_configuration.json`).

1. Get network (WiFi: `iwctl` — see [NOTES.md](NOTES.md)).
2. Edit before install:
   - Disk device: `disk_config.device_modifications[0].device` (this **wipes** the disk)
   - Hostname, auth, LUKS password (`user_credentials.json`)
   - `gfx_driver` — NVIDIA open by default; change for AMD/Intel
3. Run archinstall with the config (USB or config URL — details in [NOTES.md](NOTES.md)).

Layout: **Btrfs + LUKS + Snapper**, GNOME + GDM, PipeWire, NetworkManager.

### 2. Post-install (minimal)

After first reboot, from a clone of this repo:

```bash
./post_install.sh
```

Enables multilib, updates packages, optional NVIDIA (`setup-nvidia.sh`), and installs Kitty + build basics.

### 3. Bootstrap (full workstation)

```bash
# Do not run with sudo
bash scripts/bootstrap.sh
# bash scripts/bootstrap.sh --yes   # non-interactive (saved config / defaults)
```

You will be prompted for:

- Full name + email (git)
- Profiles (multi-select): **work**, **personal**, and/or **devcontainer**
- Whether to install NVIDIA (`nvidia-open-dkms`)
- Machine type: **laptop** or **desktop** (defaults to battery detection)

Config is saved at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`
(`FULL_NAME`, `EMAIL_ADDRESS`, `SETUP_PROFILES`, `SETUP_PROFILE` primary, `INSTALL_NVIDIA`, `MACHINE_TYPE`).

Bootstrap then: updates pacman/yay → runs all setup scripts → configures GNOME (if present) → symlinks dotfiles.

---

## Keep everything in sync

On any machine that already has this repo:

```bash
cd /path/to/dotfiles-arch
bash scripts/sync.sh
```

That will:

1. Resolve/save profiles + NVIDIA + machine type (`load_bootstrap_config` / `write_bootstrap_config`)
2. `git pull --ff-only`
3. Run a guarded system upgrade (`pacman` + AUR IoC scan + `yay`) every time
4. Re-run setup scripts via the shared `run-profile-setup.sh` list (continues on error; prints failures)
5. Relink dotfiles + `post-link-hooks.sh` (font cache, GNOME checklist)
6. Optionally remove obsolete packages (Herdr, Hyprland stack, etc.)

### Useful flags

```bash
bash scripts/sync.sh --profile work
bash scripts/sync.sh --profile work,devcontainer
bash scripts/sync.sh --profile personal
bash scripts/sync.sh --prompt               # re-ask profiles / NVIDIA / machine type
bash scripts/sync.sh --cleanup              # remove obsolete packages/configs
bash scripts/sync.sh --skip-bootstrap       # skip setup-*.sh (still upgrades + links)
bash scripts/sync.sh --yes --profile work,devcontainer --cleanup
```

With `--yes`, pass `--profile` if none is saved yet. Cleanup with `--yes` only runs when `--cleanup` is also set. Saved profiles/NVIDIA/machine type are kept silently unless unset or `--prompt`.

**Rule of thumb:** after you pull big changes on another PC, run `sync.sh` once (needs sudo for packages). Use `update-system.sh` for day-to-day package-only updates without re-running setup scripts.

---

## Profiles

Profiles are **additive** — select any combination on one machine (e.g. work + devcontainer).

| Profile | Extra setup | Default browser (Super+B) |
|---------|-------------|---------------------------|
| **work** | Cursor IDE + Agent CLI, Zoom, Slack, Chrome | Chrome (when work is selected) |
| **personal** | Steam, Discord, Firefox, Mullvad VPN, opencode | Firefox (when personal is selected and work is not) |
| **devcontainer** | just, mkcert, OpenVPN 3, DNS for `~test`, inotify watches, Dev Containers extension | — (no browser change) |

Everything else in the stack is shared (including Docker and `gh` used by the devcontainer host setup). Cursor is work-only — the devcontainer profile's Dev Containers extension step just warns and skips it if Cursor isn't installed.

---

## What's installed

### Shared stack

| Area | Tools |
|------|--------|
| **Shell / CLI** | bash, Starship, zoxide, eza, fzf, ripgrep, fd, bat, git-delta, jq, htop, btop, ncdu, duf, tldr, fastfetch, shellcheck, stow, wl-clipboard, xsel |
| **Terminal** | Kitty (Catppuccin Mocha) |
| **Multiplexer** | tmux |
| **Editors / AI** | Neovim (LazyVim-style), Claude Code (`claude`), Cursor IDE + Agent CLI (`agent`, work profile only) |
| **Git** | git, lazygit (`lzg`), GitHub CLI (`gh`) |
| **Languages** | Node (NVM LTS), Python, Rust (rustup), Go, PHP + Composer + Laravel, Ruby + Rails |
| **Containers** | Docker, Compose, Buildx, lazydocker (`lzd`), minikube, kubectl, k9s |
| **Apps** | TablePlus, Postman, Spotify, Obsidian, ZSA Keymapp (Moonlander) |
| **Fonts** | Adwaita Sans/Mono (GNOME UI), Noto + Liberation fallbacks, Meslo / Ubuntu / Fira Code / JetBrains Mono / Hack Nerd Fonts |
| **Desktop** | GNOME + Pop Shell (tiling off by default), Dash to Panel (top bar), No Overview, AppIndicator, GPaste, Papirus + Catppuccin GTK |

### GNOME extras (via `setup-gnome.sh`)

- Pop Shell available (no gaps / no hint radius; active hint on); auto-tiling **off** by default — toggle with Super+Y
- Dash to Panel: always-visible full-width top bar on every monitor (small centered app icons)
- Skip Activities overview at login
- Clipboard history (GPaste)
- Tray icons (AppIndicator)
- Night Light, dark theme, battery % in panel
- Tap-to-click **off**
- Emoji picker (`gnome-characters`) and the screenshot UI on Super shortcuts

### Power policy (`MACHINE_TYPE`)

`setup-gnome.sh` applies the saved machine type:

| | laptop | desktop |
|---|--------|---------|
| `power-profiles-daemon` | `balanced` | `performance` |
| Sleep on battery | 30 min | n/a |
| Lid on battery (`HandleLidSwitch`) | `suspend` | `ignore` |
| Lid on AC (`HandleLidSwitchExternalPower`) | `ignore` (closed-lid KVM/desk) | `ignore` |
| Lid when docked | `ignore` | `ignore` |
| USB HID/hub wake (`90-dotfiles-arch-usb-wakeup.rules`) | enabled | enabled |
| Audio power saving | on (battery life) | off (prevents popping) |

Lid drop-in: `/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf` (re-login or reboot to apply).
On AC with the lid closed, the laptop stays awake; keyboard/mouse on a KVM can also wake from suspend.

### NVIDIA

Only when `INSTALL_NVIDIA=true`. Prefers **`nvidia-open-dkms`**; does not swap an already-installed driver flavor. See [NOTES.md](NOTES.md).

---

## Shortcuts

### GNOME / window management

| Shortcut | Action |
|----------|--------|
| **Super+Return** | Kitty terminal |
| **Super+E** | Files (Home) |
| **Super+B** | Browser (Chrome or Firefox by profile) |
| **Super+Space** | Application launcher |
| **Super+V** | Clipboard history (GPaste) |
| **Super+.** | Emoji picker (`gnome-characters`) |
| **Super+Shift+S** | Screenshot UI (region / window / screen; Print also works) |
| **Super+Shift+N** | Minimize window |
| **Super+Y** | Toggle Pop Shell auto-tiling (off by default) |
| **Super+G** | Float / unfloat focused window |
| **Super+Escape** | Pop Shell tile adjustment mode |
| **Super+1…9** | Switch to workspace N |
| **Super+Shift+1…9** | Move window to workspace N |
| **Super+Alt+←/→** | Switch workspace left/right |
| **Super+Shift+Alt+←/→** | Move window left/right |
| **Super+Q** | Close window |
| **Super+F** | Fullscreen |
| **Super+M** | Maximize |
| **Super+Ctrl+←/→** | Floating: half-snap · Tiled: push window (edge → next monitor) |
| **Super+Ctrl+↑/↓** | Floating: other monitor · Tiled: push window (edge → next monitor) |
| **Super+Y** | Toggle Pop Shell tiling (rebinds Super+Ctrl+Arrows) |
| **Alt+Tab** | Switch windows |

### tmux (prefix = **Ctrl+B**)

| Keys | Action |
|------|--------|
| `tmux attach` | Attach to a session |
| `Ctrl+B` `d` | Detach (session keeps running) |
| `Ctrl+B` `%` / `"` | Split right / down |
| `Ctrl+B` `c` | New window |
| `Ctrl+B` `n` / `p` | Next / previous window |
| `Ctrl+B` `?` | All bindings |

Agents: `code <dir> --agent cursor` or `--agent claude` starts that CLI in the split pane. Without `--agent`, `code` uses `DEFAULT_AGENT` — set during `setup-code.sh` (auto-picked if only one CLI is installed, asked if both are). Cursor saved workspaces: `code <dir> --agent cursor --workspace day-to-day`. Either agent's file edits automatically reveal themselves in the Neovim pane (loaded into the edit window like a nvim-tree click, or focused/reloaded in place if already open) via the `nvim-reveal-edit` hook installed by `setup-claude.sh`/`setup-cursor.sh`.

### Shell (highlights)

| Command | What it does |
|---------|----------------|
| `code [dir]` | tmux session + `nvim .` (git repo; `--force` for non-git; `--agent cursor --workspace NAME` for Cursor CLI workspace) |
| `v` / `vim` | Neovim |
| `vimcheat` | Neovim cheat sheet |
| `lzg` / `lzd` | lazygit / lazydocker |
| `z` / `zi` | Smart cd (zoxide) |
| `r` / `repos` | fzf-pick a repo under `~/repos` and cd into it |
| `pbcopy` / `pbpaste` | Wayland clipboard in/out |
| `mvup` / `mvdown` / `mvst` | Mullvad connect / disconnect / status |
| `check` | Syntax + shellcheck the repo scripts |
| `orphans` | Remove orphaned pacman packages |
| `rebind-window-push` | Keep Super+Ctrl+Arrows on Pop Shell (tiled) or Mutter (floating) |
| `gs` `ga` `gc` `gp` `gpush` … | Git aliases (diffs paged through delta) |
| `welcome` | Shell cheat sheet |
| `aliases` | Aliases + key bindings |
| `packages` | What every installed package is for ([PACKAGES.md](PACKAGES.md)) |
| `agent --mode ask "…"` | Ask Cursor Agent from the CLI |
| `claude` | Claude Code CLI |
| `reload` | Reload `~/.bashrc` |

Readline (Tab menu-complete, history search, word jumps): see `welcome` or `~/.inputrc`.
fzf adds **Ctrl+R** (history), **Ctrl+T** (files), and **Alt+C** (cd into a subdirectory).

Kitty: **Ctrl+Shift+=/-** font size, **Ctrl+Shift+Backspace** reset, **Ctrl+Shift+F** scrollback pager, **Ctrl+Shift+E** URL hints.

Neovim: leader is **Space** — full map in `~/.nvim-cheatsheet.md` (`vimcheat`).

---

## Day-to-day workflow

1. **Terminal** — Super+Return (Kitty).
2. **Project** — `cd` / `z` into a repo, then `code` for tmux + Neovim, or open Cursor / Claude as needed.
3. **Git** — `gs` / `lzg`; GitHub with `gh`.
4. **Docker** — `dps` / `lzd`.
5. **Clipboard history** — Super+V.
6. **After repo updates** — `bash scripts/sync.sh`.

---

## Repo map

```
dotfiles-arch/
├── README.md              ← you are here
├── REFRESHER.md           ← short memory jogger
├── PACKAGES.md            ← what each installed package is for (`packages`)
├── NOTES.md               ← WiFi, archinstall, NVIDIA, sync details
├── CLAUDE.md              ← architecture notes for AI agents
├── AGENTS.md              ← pointer file for Cursor / other agents
├── .cursor/rules/         ← repo conventions for AI agents
├── post_install.sh        ← minimal post-archinstall
├── user_configuration.json
├── scripts/
│   ├── bootstrap.sh       # new machine
│   ├── sync.sh            # existing machine (always guarded upgrade)
│   ├── run-profile-setup.sh
│   ├── post-link-hooks.sh
│   ├── link-dotfiles.sh
│   ├── update-system.sh   # day-to-day pacman + yay
│   ├── fn-lib.sh          # shared helpers / AUR IoC scan
│   ├── check.sh           # bash -n + shellcheck
│   └── setup-*.sh
├── home/                  # → ~
│   └── .local/bin/        # morning, update-repos, sync-dotfiles, update-system, check-dotfiles, remove-orphans, repos, code, nvim-reveal-edit, …
└── config/                # → ~/.config
```

---

## Related docs

| Doc | Use when |
|-----|----------|
| [REFRESHER.md](REFRESHER.md) | You forgot how things work after time away |
| [PACKAGES.md](PACKAGES.md) | You want to know why a package is installed (`packages`) |
| [NOTES.md](NOTES.md) | Installing Arch or debugging GPU/sync |
| [CLAUDE.md](CLAUDE.md) | Changing scripts / understanding design |
| [AGENTS.md](AGENTS.md) | An AI agent needs the short version of the conventions |
| `welcome` (in shell) | Alias and tmux quick reference |
| `vimcheat` | Neovim keybindings |
