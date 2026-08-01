# dotfiles-arch

Arch Linux workstation setup for a **GNOME (Wayland)** development machine: Kitty, Herdr, Neovim, Cursor, Claude Code, and a modular bootstrap/sync system.

This README is the starting point. Detailed install notes live in [NOTES.md](NOTES.md). After a long break, use [REFRESHER.md](REFRESHER.md).

---

## Choose your path

| Situation | What to run |
|-----------|-------------|
| **Brand-new Arch install** | archinstall → `./post_install.sh` → `bash scripts/bootstrap.sh` |
| **Existing machine / other PC** | `bash scripts/sync.sh` |
| **Just re-link configs** | `bash scripts/link-dotfiles.sh` |
| **One tool only** | `bash scripts/setup-<tool>.sh` |

Paths use `$HOME` — different usernames on other machines are fine.

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
```

You will be prompted for:

- Full name + email (git)
- Profile: **work** or **personal**
- Whether to install NVIDIA (`nvidia-open-dkms`)

Config is saved at `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`.

Bootstrap then: updates pacman/yay → runs all setup scripts → configures GNOME (if present) → symlinks dotfiles.

---

## Keep everything in sync

On any machine that already has this repo:

```bash
cd /path/to/dotfiles-arch
bash scripts/sync.sh
```

That will:

1. Resolve/save profile + NVIDIA preference
2. `git pull --ff-only`
3. Re-run setup scripts (idempotent)
4. Relink dotfiles
5. Optionally remove obsolete packages (tmux, Hyprland stack, etc.)

### Useful flags

```bash
bash scripts/sync.sh --profile work
bash scripts/sync.sh --profile personal
bash scripts/sync.sh --cleanup              # remove obsolete packages/configs
bash scripts/sync.sh --skip-bootstrap       # pull + link only (+ optional cleanup)
bash scripts/sync.sh --yes --profile work --cleanup
```

With `--yes`, pass `--profile` if none is saved yet. Cleanup with `--yes` only runs when `--cleanup` is also set.

**Rule of thumb:** after you pull big changes on another PC, run `sync.sh` once (needs sudo for packages).

---

## Profiles

| Profile | Extra apps | Default browser (Super+B) |
|---------|------------|---------------------------|
| **work** | Zoom, Slack, Chrome | Chrome |
| **personal** | Steam, Discord, Firefox, Mullvad VPN | Firefox |

Everything else in the stack is shared.

---

## What's installed

### Shared stack

| Area | Tools |
|------|--------|
| **Shell / CLI** | bash, Starship, zoxide, eza, fzf, ripgrep, fd, bat, jq, htop, btop, ncdu, duf, tldr, fastfetch, shellcheck, stow, wl-clipboard, xsel |
| **Terminal** | Kitty (Catppuccin Mocha) |
| **Multiplexer** | Herdr (+ Claude & Cursor agent integrations) |
| **Editors / AI** | Neovim (LazyVim-style), Cursor IDE + Agent CLI (`agent`), Claude Code (`claude`) |
| **Git** | git, lazygit (`lzg`), GitHub CLI (`gh`) |
| **Languages** | Node (NVM LTS), Python, Rust (rustup), Go, PHP + Composer + Laravel, Ruby + Rails |
| **Containers** | Docker, Compose, Buildx, lazydocker (`lzd`), minikube, kubectl, k9s |
| **Apps** | TablePlus, Postman, Spotify, Obsidian, ZSA Keymapp (Moonlander) |
| **Fonts** | Meslo / Ubuntu / Fira Code / JetBrains Mono / Hack Nerd Fonts |
| **Desktop** | GNOME + Pop Shell, No Overview, AppIndicator, GPaste, Papirus + Catppuccin GTK |

### GNOME extras (via `setup-gnome.sh`)

- Pop Shell tiling (gaps, active hint)
- Skip Activities overview at login
- Clipboard history (GPaste)
- Tray icons (AppIndicator)
- Night Light, dark theme, battery % in panel
- Tap-to-click **off**

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
| `code [dir]` | Herdr workspace + `nvim .` (git repo) |
| `v` / `vim` | Neovim |
| `vimcheat` | Neovim cheat sheet |
| `lzg` / `lzd` | lazygit / lazydocker |
| `z` / `zi` | Smart cd (zoxide) |
| `gs` `ga` `gc` `gp` `gpush` … | Git aliases |
| `welcome` | Shell cheat sheet |
| `aliases` | Full alias / tool list |
| `agent --mode ask "…"` | Ask Cursor Agent from the CLI |
| `claude` | Claude Code CLI |
| `reload` | Reload `~/.bashrc` |

Readline (Tab menu-complete, history search, word jumps): see `welcome` or `~/.inputrc`.

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
├── NOTES.md               ← WiFi, archinstall, NVIDIA, sync details
├── CLAUDE.md              ← architecture notes for AI agents
├── post_install.sh        ← minimal post-archinstall
├── user_configuration.json
├── scripts/
│   ├── bootstrap.sh       # new machine
│   ├── sync.sh            # existing machine
│   ├── link-dotfiles.sh
│   └── setup-*.sh
├── home/                  # → ~
└── config/                # → ~/.config
```

---

## Related docs

| Doc | Use when |
|-----|----------|
| [REFRESHER.md](REFRESHER.md) | You forgot how things work after time away |
| [NOTES.md](NOTES.md) | Installing Arch or debugging GPU/sync |
| [CLAUDE.md](CLAUDE.md) | Changing scripts / understanding design |
| `welcome` (in shell) | Alias and Herdr quick reference |
| `vimcheat` | Neovim keybindings |
