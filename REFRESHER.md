# Refresher

## Installed DFA copies

Managed configuration, helpers, rules, skills and Pi extensions now use stable installed copies at
`~/.local/share/workstation/config`. Moving the checkout preserves runtime paths. `dfa-deploy update`
obtains shared changes, stages/merges, validates and activates one generation; conflicts preserve
live files and return failure. `dfa-deploy source` identifies the shared edit destination.
Use `dfa-deploy capture <artifact>` for one selected source improvement,
`dfa-deploy override <artifact> <file>` for a persistent local override,
`dfa-deploy rebind <checkout>` after a source move, and `dfa-deploy rollback` / `recover`
for recovery. See [deployment policy and dependency inventory](docs/deployment.md).


You have been away. This is the short version. Full detail: [README.md](README.md) · install deep dive: [NOTES.md](NOTES.md).

Arch / Ubuntu 26.04 editor setup: `bash scripts/setup-node.sh`, then
`bash scripts/setup-neovim.sh` and `bash scripts/setup-dev.sh` with the shared shell
loaded. `dev --tmux` requires stable Neovim 0.12+, tree-sitter CLI 0.26.1+, tmux 3.2+.
`dfa-update-system --force` refreshes native tools and known managed upstream editor
releases. Sources/configs are preserved; resolve conflicts explicitly. Runtime
validation remains unverified; see [the source/update matrix](PACKAGES.md#neovim-and-tmux-distro-slice).

---

## First 60 seconds

```bash
# Open a terminal
Super+Return

# Remember shell aliases
welcome
# or
aliases

# Bring this machine up to date with the repo
cd ~/repos/dotfiles-arch   # or wherever you cloned it
bash scripts/sync.sh
```

If packages need installing, sync will ask for sudo.

---

## I forgot how to…

### …open the things I use every day

| Want | Do this |
|------|---------|
| Terminal | **Super+Return** |
| Files | **Super+E** |
| Browser | **Super+B** |
| App search | **Super+Space** |
| Clipboard history | **Super+V** |
| Dictation toggle | **Super+T** |
| Emoji picker | **Super+.** |
| Screenshot (region/window/screen) | **Super+Shift+S** (or Print) |
| Minimize a window | **Super+Shift+N** |
| Close a window | **Super+Q** |

### …edit a project in Neovim the “right” way

```bash
cd /path/to/git-repo
dev             # open the project in Zed
dev --tmux      # tmux instead: nvim + agent (focus), console shell, lazygit if git repo
dev --force     # same, for a directory without .git
# or
v .             # plain Neovim in current Kitty window
```

Neovim cheat sheet: `vimcheat` (leader key is **Space**).

### …use tmux again

```bash
tmux attach           # attach to a session
tmux ls               # list sessions
# Inside: prefix is Ctrl+B
# Ctrl+B d            # detach (session keeps running)
# Ctrl+B ?             # all keys
```

Open Neovim + an agent pane together:

```bash
dev --tmux <dir> --agent claude
dev --tmux <dir> --agent codex
```

### …ask an agent from the terminal

```bash
claude
codex
```

### …git / docker TUIs

```bash
lzg    # lazygit
lzd    # lazydocker
gs     # git status
gh     # GitHub CLI
```

### …jump around directories

```bash
z project-name     # zoxide smart cd
zi                 # interactive pick
r                  # fzf-pick a repo under ~/repos and cd into it
..  ...  -         # up / back
```

Shell fuzzy keys: **Ctrl+R** history · **Ctrl+T** files · **Alt+C** cd into a subdirectory.

### …tile windows / move to another monitor

Pop Shell shortcuts below require a compatible shell (GNOME 50 target). Above
GNOME 50, its accepted gap retains native half-snap/monitor moves; Super+Y,
Super+G and Super+Escape are unavailable.

| Shortcut | Action |
|----------|--------|
| **Super+Ctrl+←/→** | Floating: half-snap · Tiled: push in layout (edge → monitor) |
| **Super+Ctrl+↑/↓** | Floating: other monitor · Tiled: push in layout (edge → monitor) |
| **Super+Y** | Toggle Pop Shell auto-tiling (off by default; rebinds Super+Ctrl+Arrows) |
| **Super+G** | Float / unfloat focused window |
| **Super+Escape** | Pop Shell tile adjustment mode |
| **Super+1…9** | Jump to workspace |
| **Super+Shift+1…9** | Move window to workspace |

Top app bar (Dash to Panel) is always visible on every monitor — small centered icons, full width.

### …update packages safely (instead of raw yay -Syu)

```bash
bash scripts/update-system.sh           # interactive
bash scripts/update-system.sh --yes     # after IoC scan, non-interactive
bash scripts/update-system.sh --scan-only
bash scripts/update-system.sh --force   # bypass the 1-day cooldown
```

Scans pending AUR PKGBUILDs for known supply-chain IoCs before upgrading. Skips the
actual upgrade (no prompts) if the last one ran within 24h; `--force` overrides.
On Btrfs installs it also reminds you about Snapper: `sudo snapper -c root list`,
or `sudo snapper -c root create -d "before <change>"` ahead of a risky upgrade.

Housekeeping: `orphans` previews native removal candidates; `dfa-remove-orphans --remove`
requires terminal confirmation (`--yes` alone is insufficient). `dfa-daily`/`dfa-weekly`
use guarded pacman/AUR on Arch and APT on Ubuntu 26.04; weekly cleanup only previews.
Bootstrap/sync use the same additive profile runner on both hosts. `check` runs shellcheck over the repo scripts.

### …fix ugly Courier-like title / UI fonts

```bash
bash scripts/setup-fonts.sh
bash scripts/setup-gnome.sh   # or full: bash scripts/sync.sh
```

Shared stack: **Adwaita Sans** (UI/title), **JetBrainsMono Nerd Font** (mono / Kitty). Then log out/in if apps still look wrong.

### …sync after I changed the repo on another machine

```bash
cd /path/to/dotfiles-arch
git pull
bash scripts/sync.sh
```

Or let sync pull for you:

```bash
bash scripts/sync.sh --profile work,devcontainer   # or personal / work only
bash scripts/sync.sh --cleanup           # preview native orphans + Arch obsolete packages
```

### …set up a brand-new Arch box

1. `./prepare-archinstall.sh` — picks disk/hostname/gfx_driver into `user_configuration.json`; creds still manual
2. archinstall with `user_configuration.json` — see NOTES
3. `./post_install.sh` — chains straight into bootstrap (name, email, work|personal, NVIDIA y/n, laptop|desktop); re-run `bash scripts/bootstrap.sh` on its own later if needed

### …set up an installed Ubuntu 26.04 GNOME machine

Run `bash scripts/bootstrap.sh` as your user with sudo and source-registration permission.
The installed GNOME desktop is required; disk provisioning remains Arch-only.
Sources/update owners: [PACKAGES.md](PACKAGES.md) and [audit](docs/ubuntu-source-update-audit.md).
Runtime paths: [validation inventory](docs/ubuntu-integration-validation.md).

### …remember work vs personal

| Profile | Extra | Browser |
|---------|-------|---------|
| **work** | Zoom, Slack, Chrome | Chrome |
| **personal** | Steam, Discord, Firefox, Mullvad (Arch / Ubuntu 26.04) | Firefox; selected known-owner launcher, work still wins |

Saved in `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`, along with
`MACHINE_TYPE=laptop|desktop`, which drives the power profile, lid behavior
(laptop: suspend on battery lid-close, ignore on AC/docked; USB HID wake for
KVM), and audio power saving. Re-ask any saved answer with
`bash scripts/sync.sh --prompt`.

### …find a tool that should already be installed

```bash
packages         # what every installed package is for (PACKAGES.md)
aliases          # aliases + key bindings
command -v tmux kitty nvim claude codex ollama
```

Shared highlights: Kitty, tmux, Neovim, Claude Code, Codex, Ollama, Docker, lazygit, Node (nvm), Rust, Go, PHP, Ruby, Spotify, Obsidian, TablePlus, Postman.

GPU-only Ollama: `bash scripts/setup-ollama.sh` on Arch / Ubuntu 26.04; working
CUDA or hardware Vulkan 1.2+ required. Ubuntu archives use a user service
(`systemctl --user status ollama`, `journalctl --user -u ollama`); native packages
retain their system service. `dfa-update-system` refreshes managed archives and
reports service failures. NVIDIA setup requires explicit saved opt-in or
`bash scripts/setup-nvidia.sh --install`; `--yes` does not opt in. Existing
drivers are never replaced; reboot/MOK activation can remain pending. See
[GPU sources and requirements](PACKAGES.md#gpu-sources-capability-gates-and-update-owners).

Dictation: `bash scripts/setup-voxtype.sh`, then **Super+T**. dotool needs writable
`/dev/uinput`; setup reports pending group/login/rule access as failure. User
config/backend/models stay yours. `dfa-update-system` refreshes installers only;
separate model download: `voxtype setup --download --model base.en --no-post-install`.
Start a disabled service explicitly with `systemctl --user enable --now voxtype.service`.
See [dictation sources and runtime limits](PACKAGES.md#dictation-sources-and-update-owners).

Desktop utility setup also supports Ubuntu 26.04: `setup-tableplus.sh`,
`setup-postman.sh`, `setup-spotify.sh`, `setup-obsidian.sh`, `setup-moonlander.sh`.
`dfa-update-system` maintains vendor APT, Obsidian's separate Electron installer,
and the verified Keymapp pin; Snap and writable Postman archive self-updates retain
their owners/settings. A changed Keymapp archive requires a reviewed pin update.
After first ZSA setup, log out/in and replug the keyboard. Runtime remains unverified;
see [sources and limits](PACKAGES.md#desktop-utility-sources-and-update-owners).

Language-only setup on Arch / Ubuntu 26.04: choose from
`scripts/setup-{python,rust,golang,php,ruby}.sh` and run with Bash
(for example `bash scripts/setup-python.sh`). Native packages update with `dfa-update-system`; user
toolchains/gems stay manual: `rustup update`,
`gem update --user-install <user-gem> --no-document` (Bundler/Rails only when user-owned),
`composer global update laravel/installer`. Use `python3 -m venv .venv` for project
Python packages. See `packages` for sources, conflicts and unverified runtime paths.

### …reload shell config after editing bashrc

```bash
reload
# or
source ~/.bashrc
```

Dotfiles are **symlinks** into this repo — edit in the repo, changes apply immediately for linked files. New files need `bash scripts/link-dotfiles.sh` (or sync).

---

## Cheat pocket card

```
Super+Return     terminal          Ctrl+B …     tmux prefix
Super+E          files             Ctrl+B d     detach tmux
                                   dev          Zed (--tmux: nvim)
Super+B          browser           lzg / lzd    git / docker TUI
Super+V          clipboard hist    z / zi / r   smart cd / repo pick
Super+.          emoji             Ctrl+R       fuzzy history
Super+Shift+S    screenshot        Ctrl+T       fuzzy file
Super+Shift+N    minimize          Alt+C        fuzzy cd
Super+Space      apps              welcome      this environment
Super+Q          close             packages     what each package is for
Super+1-9        workspaces        sync.sh      update machine
```

---

## Still stuck?

1. `welcome` / `aliases` / `packages` / `vimcheat` in the shell  
2. [README.md](README.md) — full shortcuts + install/sync  
3. [PACKAGES.md](PACKAGES.md) — what each installed package is for  
4. [NOTES.md](NOTES.md) — WiFi, archinstall, NVIDIA  
5. Ask the agent: `agent --mode ask "…"`
