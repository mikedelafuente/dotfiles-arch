# Refresher

You have been away. This is the short version. Full detail: [README.md](README.md) · install deep dive: [NOTES.md](NOTES.md).

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
| Herdr session | **Super+Shift+Return** |
| Files | **Super+E** |
| Browser | **Super+B** |
| App search | **Super+Space** |
| Clipboard history | **Super+V** |
| Emoji picker | **Super+.** |
| Screenshot (region/window/screen) | **Super+Shift+S** (or Print) |
| Minimize a window | **Super+Shift+N** |
| Close a window | **Super+Q** |

### …edit a project in Neovim the “right” way

```bash
cd /path/to/git-repo
code            # Herdr + nvim .  (must be a git repo)
code --force    # same, for a directory without .git
# or
v .             # plain Neovim in current Kitty window
```

Neovim cheat sheet: `vimcheat` (leader key is **Space**).

### …use Herdr again

```bash
herdr                 # attach or create
# Inside: prefix is Ctrl+B
# Ctrl+B q            # detach (leave agents running)
# Ctrl+B ?            # all keys
```

Open Neovim + an agent pane together:

```bash
code <dir> --agent cursor
code <dir> --agent cursor --workspace day-to-day
code <dir> --agent claude
```

Or start an agent pane by hand (raw CLI):

```bash
herdr agent start my-job --kind cursor --pane <id>
herdr agent start my-job --kind claude --pane <id>
```

### …ask Cursor from the terminal

```bash
agent --mode ask "How does sync.sh decide the profile?"
agent -p --mode ask "Summarize setup-gnome.sh shortcuts"
```

IDE: just run `cursor`. Claude CLI: `claude`.

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
```

Scans pending AUR PKGBUILDs for known supply-chain IoCs before upgrading.
On Btrfs installs it also reminds you about Snapper: `sudo snapper -c root list`,
or `sudo snapper -c root create -d "before <change>"` ahead of a risky upgrade.

Housekeeping: `orphans` removes orphaned packages, `check` runs shellcheck over the repo scripts.

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
bash scripts/sync.sh --cleanup           # drop old tmux/hypr/ghostty junk
```

### …set up a brand-new Arch box

1. archinstall with `user_configuration.json` (set disk + creds — see NOTES)
2. `./post_install.sh`
3. `bash scripts/bootstrap.sh` (name, email, work|personal, NVIDIA y/n, laptop|desktop)

### …remember work vs personal

| Profile | Extra | Browser |
|---------|-------|---------|
| **work** | Zoom, Slack, Chrome | Chrome |
| **personal** | Steam, Discord, Firefox, Mullvad | Firefox |

Saved in `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`, along with
`MACHINE_TYPE=laptop|desktop`, which drives the power profile, lid behavior
(laptop: suspend on battery lid-close, ignore on AC/docked; USB HID wake for
KVM), and audio power saving. Re-ask any saved answer with
`bash scripts/sync.sh --prompt`.

### …find a tool that should already be installed

```bash
packages         # what every installed package is for (PACKAGES.md)
aliases          # aliases + key bindings
command -v herdr kitty nvim agent claude
```

Shared highlights: Kitty, Herdr, Neovim, Cursor + `agent`, Claude, Docker, lazygit, Node (nvm), Rust, Go, PHP, Ruby, Spotify, Obsidian, TablePlus, Postman.

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
Super+Return     terminal          Ctrl+B …     Herdr prefix
Super+Shift+Ret  herdr session     Ctrl+B q     detach Herdr
Super+E          files             code         herdr + nvim
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
