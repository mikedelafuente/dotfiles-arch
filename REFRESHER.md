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
| Files | **Super+E** |
| Browser | **Super+B** |
| App search | **Super+Space** |
| Clipboard history | **Super+V** |
| Close a window | **Super+Q** |

### …edit a project in Neovim the “right” way

```bash
cd /path/to/git-repo
code          # Herdr + nvim .  (must be a git repo)
# or
v .           # plain Neovim in current Kitty window
```

Neovim cheat sheet: `vimcheat` (leader key is **Space**).

### …use Herdr again

```bash
herdr                 # attach or create
# Inside: prefix is Ctrl+B
# Ctrl+B q            # detach (leave agents running)
# Ctrl+B ?            # all keys
```

Start an agent pane:

```bash
herdr agent start my-job -- cursor
herdr agent start my-job -- claude
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
..  ...  -         # up / back
```

### …tile windows / move to another monitor

| Shortcut | Action |
|----------|--------|
| **Super+Ctrl+←/→** | Tile left/right on this screen |
| **Super+Ctrl+↑/↓** | Send window to the other monitor |
| **Super+Y** | Toggle Pop Shell auto-tiling |
| **Super+G** | Float / unfloat focused window |
| **Super+Escape** | Pop Shell tile adjustment mode |
| **Super+1…9** | Jump to workspace |
| **Super+Shift+1…9** | Move window to workspace |

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
bash scripts/sync.sh --profile work      # or personal
bash scripts/sync.sh --cleanup           # drop old tmux/hypr/ghostty junk
```

### …set up a brand-new Arch box

1. archinstall with `user_configuration.json` (set disk + creds — see NOTES)
2. `./post_install.sh`
3. `bash scripts/bootstrap.sh` (name, email, work|personal, NVIDIA y/n)

### …remember work vs personal

| Profile | Extra | Browser |
|---------|-------|---------|
| **work** | Zoom, Slack, Chrome | Chrome |
| **personal** | Steam, Discord, Firefox, Mullvad | Firefox |

Saved in `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`.

### …find a tool that should already be installed

Shared highlights: Kitty, Herdr, Neovim, Cursor + `agent`, Claude, Docker, lazygit, Node (nvm), Rust, Go, PHP, Ruby, Spotify, Obsidian, TablePlus, Postman.

```bash
aliases          # lists tools + whether they are on PATH
command -v herdr kitty nvim agent claude
```

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
Super+E          files             Ctrl+B q     detach Herdr
Super+B          browser           code         herdr + nvim
Super+V          clipboard hist    lzg / lzd    git / docker TUI
Super+Space      apps              z / zi       smart cd
Super+Q          close             welcome      this environment
Super+1-9        workspaces        sync.sh      update machine
```

---

## Still stuck?

1. `welcome` / `aliases` / `vimcheat` in the shell  
2. [README.md](README.md) — full shortcuts + install/sync  
3. [NOTES.md](NOTES.md) — WiFi, archinstall, NVIDIA  
4. Ask the agent: `agent --mode ask "…"`
