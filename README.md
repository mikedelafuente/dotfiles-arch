# dotfiles-arch

Arch Linux workstation setup for a **GNOME (Wayland)** development machine: Kitty, Herdr, Neovim, Cursor, Claude Code, and a modular bootstrap/sync system.

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
update-system                 # after link-dotfiles; or:
bash scripts/update-system.sh
bash scripts/update-system.sh --yes        # non-interactive after clean AUR scan
bash scripts/update-system.sh --scan-only  # scan pending AUR upgrades only
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
6. Optionally remove obsolete packages (tmux, Hyprland stack, etc.)

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
| **work** | Zoom, Slack, Chrome | Chrome (when work is selected) |
| **personal** | Steam, Discord, Firefox, Mullvad VPN | Firefox (when personal is selected and work is not) |
| **devcontainer** | just, mkcert, OpenVPN 3, DNS for `~test`, inotify watches, Dev Containers extension | — (no browser change) |

Everything else in the stack is shared (including Docker and `gh` used by the devcontainer host setup).

---

## What's installed

### Shared stack

| Area | Tools |
|------|--------|
| **Shell / CLI** | bash, Starship, zoxide, eza, fzf, ripgrep, fd, bat, git-delta, jq, htop, btop, ncdu, duf, tldr, fastfetch, shellcheck, stow, wl-clipboard, xsel |
| **Terminal** | Kitty (Catppuccin Mocha) |
| **Multiplexer** | Herdr (+ Claude & Cursor agent integrations) |
| **Editors / AI** | Neovim (LazyVim-style), Cursor IDE + Agent CLI (`agent`), Claude Code (`claude`) |
| **Git** | git, lazygit (`lzg`), GitHub CLI (`gh`) |
| **Languages** | Node (NVM LTS), Python, Rust (rustup), Go, PHP + Composer + Laravel, Ruby + Rails |
| **Containers** | Docker, Compose, Buildx, lazydocker (`lzd`), minikube, kubectl, k9s |
| **Apps** | TablePlus, Postman, Spotify, Obsidian, ZSA Keymapp (Moonlander) |
| **Fonts** | Adwaita Sans/Mono (GNOME UI), Noto + Liberation fallbacks, Meslo / Ubuntu / Fira Code / JetBrains Mono / Hack Nerd Fonts |
| **Desktop** | GNOME + Pop Shell, No Overview, AppIndicator, GPaste, Papirus + Catppuccin GTK |

### GNOME extras (via `setup-gnome.sh`)

- Pop Shell tiling (gaps, active hint)
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
| Lid switch (`/etc/systemd/logind.conf.d/dotfiles-arch-lid.conf`) | `suspend` | `ignore` |
| Audio power saving | on (battery life) | off (prevents popping) |

Lid changes take effect after a re-login or reboot.

### NVIDIA

Only when `INSTALL_NVIDIA=true`. Prefers **`nvidia-open-dkms`**; does not swap an already-installed driver flavor. See [NOTES.md](NOTES.md).

---

## Shortcuts

### GNOME / window management

| Shortcut | Action |
|----------|--------|
| **Super+Return** | Kitty terminal |
| **Super+Shift+Return** | Kitty running Herdr |
| **Super+E** | Files (Home) |
| **Super+B** | Browser (Chrome or Firefox by profile) |
| **Super+Space** | Application launcher |
| **Super+V** | Clipboard history (GPaste) |
| **Super+.** | Emoji picker (`gnome-characters`) |
| **Super+Shift+S** | Screenshot UI (region / window / screen; Print also works) |
| **Super+Shift+N** | Minimize window |
| **Super+Y** | Toggle Pop Shell auto-tiling |
| **Super+G** | Float / unfloat focused window |
| **Super+Escape** | Pop Shell tile adjustment mode |
| **Super+1…9** | Switch to workspace N |
| **Super+Shift+1…9** | Move window to workspace N |
| **Super+Alt+←/→** | Switch workspace left/right |
| **Super+Shift+Alt+←/→** | Move window left/right |
| **Super+Q** | Close window |
| **Super+F** | Fullscreen |
| **Super+M** | Maximize |
| **Super+Ctrl+←/→** | Tile left/right on this monitor |
| **Super+Ctrl+↑/↓** | Move window to other monitor (side-by-side layouts) |
| **Super+Y** | Toggle Pop Shell tiling |
| **Alt+Tab** | Switch windows |

### Herdr (prefix = **Ctrl+B**)

| Keys | Action |
|------|--------|
| `herdr` | Attach / create session |
| `Ctrl+B` then `q` | Detach (agents keep running) |
| `Ctrl+B` `v` / `-` | Split right / down |
| `Ctrl+B` `c` | New tab |
| `Ctrl+B` `n` / `p` | Next / previous tab |
| `Ctrl+B` `?` | All bindings |

Agents: `herdr agent start <name> -- cursor` or `claude`.

### Shell (highlights)

| Command | What it does |
|---------|----------------|
| `code [dir]` | Herdr workspace + `nvim .` (git repo; `--force` for non-git) |
| `v` / `vim` | Neovim |
| `vimcheat` | Neovim cheat sheet |
| `lzg` / `lzd` | lazygit / lazydocker |
| `z` / `zi` | Smart cd (zoxide) |
| `r` / `repos` | fzf-pick a repo under `~/repos` and cd into it |
| `pbcopy` / `pbpaste` | Wayland clipboard in/out |
| `mvup` / `mvdown` / `mvst` | Mullvad connect / disconnect / status |
| `check` | Syntax + shellcheck the repo scripts |
| `orphans` | Remove orphaned pacman packages |
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
2. **Project** — `cd` / `z` into a repo, then `code` for Herdr + Neovim, or open Cursor / Claude as needed.
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
│   └── .local/bin/        # sync-dotfiles, update-system, check-dotfiles, remove-orphans, repos, code, …
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
| `welcome` (in shell) | Alias and Herdr quick reference |
| `vimcheat` | Neovim keybindings |
