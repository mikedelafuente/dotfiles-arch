# Packages

What every package this repo installs is for, and which command or shortcut it powers.

Read it in a terminal with `packages` (linked to `~/.packages.md`).

**Keep this in sync with the `setup-*.sh` scripts** — especially `ESSENTIAL_PACKAGES`
in [scripts/setup-essentials.sh](scripts/setup-essentials.sh). Only meaningful,
directly-installed packages are listed; transitive dependencies are not.

---

## Essentials — `setup-essentials.sh`

| Package | Purpose | Related commands |
|---------|---------|------------------|
| `git` | Version control | `ga`, `gs`, `gcm`, `glog`, … |
| `git-delta` | Syntax-highlighted git diffs | pager for `git diff` / `git show` (via `.gitconfig`) |
| `curl` | HTTP transfers | `myip`, install scripts |
| `wget` | File downloads | — |
| `wl-clipboard` | Wayland clipboard | `pbcopy`, `pbpaste`, `wl-copy`, `wl-paste` |
| `xsel` | X11 clipboard fallback (XWayland apps) | `xsel` |
| `eza` | Modern `ls` with icons | `ls`, `ll`, `la`, `l`, `lt` |
| `starship` | Shell prompt (Catppuccin) | prompt; config `~/.config/starship.toml` |
| `fzf` | Fuzzy finder | Ctrl-R history, Ctrl-T files, Alt-C cd, `repos`, `r` |
| `ripgrep` | Fast recursive search | `rg`; also used by AUR IoC scans |
| `fd` | Fast `find` replacement | `fd`; backs `FZF_DEFAULT_COMMAND` |
| `bat` | Syntax-highlighted pager | `welcome`, `packages`, `vimcheat`, `MANPAGER` |
| `htop` | Interactive process viewer | `htop` |
| `btop` | Richer resource monitor | `btop` |
| `ncdu` | Disk usage explorer | `ncdu` |
| `duf` | Friendly `df` | `duf` |
| `tree` | Directory tree | `tree` |
| `jq` | JSON processor | `jq` |
| `net-tools` | Legacy net utilities | `ports` (`netstat`), `ifconfig` |
| `stow` | Symlink farm manager | manual dotfile experiments |
| `shellcheck` | Shell static analysis | `check` / `check-dotfiles`, CI |
| `github-cli` | GitHub from the terminal | `gh`; also the git credential helper |
| `tldr` | Example-first man pages | `tldr <cmd>` |
| `fastfetch` | System summary | `fastfetch` |
| `zoxide` | Directory jumping that learns | `z`, `zi`, `zq` |
| `linux-firmware-intel` | Intel firmware (only on Intel hardware) | — |

## Shell, terminal, and editor

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| `bash` | `setup-bash.sh` | Login shell | `~/.bashrc`, `~/.inputrc` |
| `kitty` | `setup-kitty.sh` | GPU terminal (Catppuccin Mocha) | Super+Return, Ctrl+Shift+F scrollback, Ctrl+Shift+E URL hints |
| `herdr-bin` (AUR) | `setup-herdr.sh` | Agent-friendly multiplexer | `herdr`, `code`, Super+Shift+Return |
| `neovim` | `setup-neovim.sh` | Editor | `v`, `vim`, `nvim`, `code` |
| `gcc`, `make` | `setup-neovim.sh` | Build Treesitter parsers / native plugins | — |
| `python-pynvim` | `setup-neovim.sh` | Neovim Python provider | — |
| `tree-sitter-cli` | `setup-neovim.sh` | Treesitter grammars | `:TSUpdate` |
| `lazygit` | `setup-git.sh` | Git TUI | `lzg` |
| `lazydocker` (AUR) | `setup-docker.sh` / `setup-code.sh` | Docker TUI | `lzd` |
| `cursor-bin` (AUR) | `setup-cursor.sh` | Cursor IDE | `cursor` |
| `cursor-cli` (AUR) | `setup-cursor.sh` | Cursor Agent CLI | `cursor-agent`, `agent` |

## Fonts — `setup-fonts.sh`

| Package | Purpose |
|---------|---------|
| `adwaita-fonts` | GNOME 48+ UI font (Adwaita Sans / Mono) |
| `noto-fonts` | Broad Unicode coverage |
| `noto-fonts-emoji` | Color emoji (Super+. picker, chat apps) |
| `ttf-liberation` | Metric-compatible Arial/Times substitutes |
| `ttf-jetbrains-mono-nerd` | Kitty / Neovim terminal font with icons |
| `ttf-meslo-nerd`, `ttf-ubuntu-nerd`, `ttf-firacode-nerd`, `ttf-hack-nerd` | Alternate Nerd Fonts |

## Desktop / GNOME — `setup-gnome.sh`

| Package | Purpose | Related commands |
|---------|---------|------------------|
| `gnome-tweaks` | Appearance and behavior tweaks | `gnome-tweaks` |
| `gnome-shell-extensions` | Base extension set | — |
| `dconf-editor` | Inspect/edit gsettings | `dconf-editor` |
| `power-profiles-daemon` | Balanced/performance power profiles | `powerprofilesctl`; driven by `MACHINE_TYPE` |
| `gnome-characters` | Emoji / special character picker | Super+. |
| `gpaste` | Clipboard history | Super+V, `gpaste-client` |
| `gnome-shell-extension-appindicator` | Tray icons (Slack, Spotify, …) | — |
| `gnome-shell-extension-dash-to-panel` | Always-visible full-width top app bar (small centered icons, every monitor) | — |
| `gnome-shell-extension-pop-shell-git` (AUR) | Tiling window management | Super+Y, Super+G, Super+Escape |
| `gnome-shell-extension-no-overview` (AUR) | Skip the overview at login | — |
| `papirus-icon-theme` | Icon theme | — |
| `papirus-folders-catppuccin-git` (AUR) | Catppuccin folder colors | `papirus-folders` |
| `catppuccin-gtk-theme-mocha` (AUR) | GTK theme | — |

## Languages and runtimes

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| `python`, `python-pip` | `setup-python.sh` | Python toolchain | `py`, `pip`, `serve`, `jsonpp` |
| `go`, `gopls` | `setup-golang.sh` | Go toolchain + LSP | `go` |
| `rustup` | `setup-rust.sh` | Rust toolchains | `cargo`, `rustc` |
| `ruby`, `sqlite`, `base-devel` | `setup-ruby.sh` | Ruby / Rails development | `ruby`, `rails` |
| `php`, `php-gd`, `php-intl`, `php-sqlite`, `php-pgsql`, `composer` | `setup-php.sh` | PHP development | `php`, `composer` |
| NVM + Node LTS (not pacman) | `setup-node.sh` | Node via NVM at `~/.config/nvm` | `nvm`, `node`, `npm` |
| Claude Code (user-level npm) | `setup-claude.sh` | Claude Code CLI | `claude` |

## Containers and Kubernetes

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| `docker`, `docker-compose`, `docker-buildx` | `setup-docker.sh` | Containers | `d`, `dc`, `dcu`, `dcd`, `dps`, `dex` |
| `minikube` | `setup-minikube.sh` | Local Kubernetes cluster | `minikube` |
| `kubectl` | `setup-minikube.sh` | Kubernetes CLI | `kubectl` |
| `k9s` | `setup-minikube.sh` | Kubernetes TUI | `k9s` |

## Tools and applications (shared)

| Package | Script | Purpose |
|---------|--------|---------|
| `tableplus` (AUR) | `setup-tableplus.sh` | Database GUI |
| `postman-bin` (AUR) | `setup-postman.sh` | API client |
| `spotify` (AUR) | `setup-spotify.sh` | Music |
| `obsidian` (AUR) | `setup-obsidian.sh` | Notes |
| `zsa-keymapp-bin` (AUR) | `setup-moonlander.sh` | ZSA Moonlander keyboard flashing |

## Profile extras

Profiles are **additive multi-select** — enable any combination on one machine
(`SETUP_PROFILES`, e.g. `work devcontainer`). Shared stack always installs first.

### work — `setup-zoom.sh`, `setup-slack.sh`, `setup-chrome.sh`

| Package | Purpose |
|---------|---------|
| `zoom` (AUR) | Meetings |
| `slack-desktop` (AUR) | Team chat |
| `google-chrome` (AUR) | Work browser (Super+B when work is selected) |

### personal — `setup-steam.sh`, `setup-discord.sh`, `setup-firefox.sh`, `setup-mullvad.sh`

| Package | Purpose | Related commands |
|---------|---------|------------------|
| `steam` (multilib) | Games | — |
| `discord` (AUR) | Chat | — |
| `firefox` | Personal browser (Super+B when personal is selected and work is not) | — |
| `mullvad-vpn-bin` (AUR) | VPN | `mvup`, `mvdown`, `mvst` |

### devcontainer — `setup-devcontainer.sh`

Host prerequisites for the platform / work devcontainer sandbox.
Docker, GitHub CLI, and Cursor are already on the shared stack; this profile adds
the rest of the host checklist (tools, DNS, watches, CA trust).

| Package / config | Purpose | Related commands |
|------------------|---------|------------------|
| `just` | Host lifecycle recipes in the devcontainer repo | `just`, `just --list` |
| `mkcert` | Local TLS CA + certs for project `*.test` domains | `mkcert -install` |
| `nss` | Firefox/trust-store support used by mkcert | — |
| `bind` | `dig` for DNS smoke checks to port 5354 | `dig @127.0.0.1 -p 5354 …` |
| `openvpn3` (AUR) | OpenVPN 3 Linux client (CloudConnexa / work VPN). Official docs only cover apt/dnf; AUR ships the same `openvpn3-linux` project. | `openvpn3 config-import`, `session-start`, `sessions-list`, `session-manage` |
| Cursor extension `ms-vscode-remote.remote-containers` | “Reopen in Container” | — |
| `/etc/systemd/resolved.conf.d/dotfiles-arch-test.conf` | Route `Domains=~test` to `127.0.0.1:5354` | restart `systemd-resolved` |
| `/etc/sysctl.d/99-dotfiles-arch-inotify.conf` | Raise `fs.inotify.max_user_watches` to 524288 | — |

## Graphics (optional)

| Package | Script | Purpose |
|---------|--------|---------|
| `nvidia-open-dkms`, `nvidia-utils`, `nvidia-settings`, `linux-headers` | `setup-nvidia.sh` | NVIDIA drivers, installed only when `INSTALL_NVIDIA=true` |

## Build / AUR plumbing

| Package | Where | Purpose |
|---------|-------|---------|
| `base-devel` | `ensure_yay_installed` | Build AUR packages |
| `yay` (AUR, built from source) | `ensure_yay_installed` | AUR helper; installs are IoC-scanned first |

---

## Related docs

- [README.md](README.md) — setup and daily flows
- [REFRESHER.md](REFRESHER.md) — keyboard shortcuts and short memory jogger
- [home/.welcome.md](home/.welcome.md) — the `welcome` cheat sheet
