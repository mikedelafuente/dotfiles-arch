# dotfiles-arch

Arch Linux workstation setup for a **GNOME (Wayland)** development machine: Kitty, tmux, Neovim, Claude Code, Codex, and a modular bootstrap/sync system.

This README is the starting point. Detailed install notes live in [NOTES.md](NOTES.md). After a long break, use [REFRESHER.md](REFRESHER.md).

Ubuntu support is incremental: **standalone Kitty, shared shell/core CLI, Neovim/tmux, agent harness setup, containers/devcontainer host prerequisites, work apps, and package maintenance**
and shared desktop utilities are available on Ubuntu 26.04, on x86_64/amd64. From the checkout, run `bash scripts/setup-kitty.sh`.
It uses the native `kitty` package, links only Kitty's shared config/theme, and
retains compatible native installations. Conflicting launchers or user config
entries cause a failure before installation; resolve them explicitly and rerun.
The script also applies the existing KDE/GNOME terminal preferences when their
tools are available. It does not install fonts: JetBrainsMono Nerd Font is the
shared preference; Kitty falls back to an installed monospace font when absent.

Container standalone setup: `bash scripts/setup-docker.sh`,
`bash scripts/setup-minikube.sh`, `bash scripts/setup-devcontainer.sh` (as your user).
Docker uses native Arch/Ubuntu Engine, Compose and Buildx packages; other providers
are preserved and reported as conflicts. Ubuntu Kubernetes tools use verified user
releases, refreshed by `dfa-update-system`. Devcontainer setup adds native CLI tools,
OpenVPN3 (scanned AUR on Arch), user-owned mkcert CA trust, `~test` split DNS and
watcher limits. Split DNS requires active systemd-resolved with its resolver stub;
existing alternate resolver policy is preserved and reported as a gap.
See [PACKAGES.md](PACKAGES.md#container-source-and-update-contract) for sources,
update owners and unverified runtime behavior. No setup/service/VPN operations
are executed as tests.

Work apps: `bash scripts/setup-chrome.sh`, `bash scripts/setup-slack.sh`, and
`bash scripts/setup-zoom.sh` support both hosts. Ubuntu selects scoped vendor APT
for Chrome/Slack and a signature-verified official Zoom DEB. `dfa-update-system`
maintains all three, including Zoom's standalone refresh. Existing launchers,
sources, holds, and user settings are retained; unknown/duplicate ownership fails.
The shared additive `work` selection and Chrome browser identity stay unchanged;
full Ubuntu profile/GNOME orchestration remains guarded. See
[work app sources and runtime limits](PACKAGES.md#work-app-sources-and-update-owners).

Shared desktop utilities: run the existing `scripts/setup-tableplus.sh`,
`setup-postman.sh`, `setup-spotify.sh`, `setup-obsidian.sh` or `setup-moonlander.sh`.
Ubuntu uses scoped vendor APT for TablePlus/Spotify, an official Postman Snap,
a verified Obsidian installer DEB and a reviewed Keymapp archive pin. Existing
official Snaps and writable user Postman archives retain their update owners.
`dfa-update-system` covers the installer/archive owners; Obsidian's in-app updater
cannot refresh Electron. Changed Keymapp bytes require a reviewed pin update.
ZSA permissions require logout/login and keyboard replug after first setup;
conflicting user udev files are preserved. See
[desktop utility sources, update owners and unverified runtime](PACKAGES.md#desktop-utility-sources-and-update-owners).

All entrypoints using the common header detect `/etc/os-release` and architecture
before mutation. Unconverted entrypoints, including bootstrap, sync (even
`--skip-bootstrap`), and the profile runner reject Ubuntu. User-only daily sync
steps are enabled; historical Arch setup migrations still fail safely on Ubuntu.
Other distros/releases/architectures are unsupported; Arch remains rolling-only.
Ubuntu Kitty updates belong to APT through `dfa-update-system`, using existing
configured sources. Daily/weekly sequencing is shared. If a repo pull triggers
full resync on Ubuntu, that guarded step reports failure and remaining daily
steps continue; full orchestration is a subsequent slice. Weekly NinjaOne health
checks run on both hosts; IT-managed installations are
checked read-only. Standalone opt-in native Ubuntu installation/removal is described
in [NinjaOne lifecycle and validation limits](PACKAGES.md#ninjaone-standalone-lifecycle--arch--ubuntu-2604).
See [Kitty sources and validation limits](PACKAGES.md#kitty-distro-slice).

The shared shell/core CLI slice also supports these standalone commands:

```bash
bash scripts/setup-essentials.sh
bash scripts/setup-bash.sh
bash scripts/setup-git.sh                 # keeps machine-local/saved identity
bash scripts/setup-github-cli.sh
bash scripts/setup-node.sh                # user-owned NVM, no sudo
```

Pass name/email to Git setup to change identity explicitly. Existing user configs
and foreign command sources are preserved and reported as conflicts; resolve them
before rerunning. Ubuntu `fd`/`bat` get executable links, Glow uses Charm's scoped
APT repository, and the remaining CLI packages use native sources. Native updates
belong to `dfa-update-system`; NVM files to standalone Node setup after pin updates;
Node LTS to `nvm install --lts` with an explicitly selected default. See the
[full command/source/version/update matrix and unverified paths](PACKAGES.md#shared-shell-and-core-cli-distro-slice).

Standalone `setup-claude.sh`, `setup-codex.sh`, `setup-pi.sh`, and
`setup-opencode.sh` now support both hosts after user-owned Node setup. Ubuntu
opencode uses stable `opencode-ai` through user npm; Arch retains native packages.
Codex setup retains the selected official ChatGPT desktop application: guarded
AUR on Arch, OpenAI's signed APT repository on Ubuntu. ChatGPT updates use
`dfa-update-system`; npm-owned harnesses use `dfa-update-npm-clis`.
See [sources, conflicts, hook inspection, and unverified paths](PACKAGES.md#agent-harnesses-and-chatgpt-distro-slice).

`dfa-update-npm-clis` also recognizes official user-native Claude installations
and runs `claude update` without NVM/npm or root ownership changes. Unknown agent
sources still report conflicts; no duplicate npm install is added.

The shared editor slice supports `bash scripts/setup-neovim.sh` and
`bash scripts/setup-dev.sh` on both hosts. Run Node setup first, then load the shared
shell so `USER_HOME_DIR/.local/bin` is on PATH. Neovim **0.12+**, tree-sitter CLI
**0.26.1+**, and tmux **3.2+** are required; `dev --tmux` checks these before
recreating a session. Compatible native tools keep their update owner; missing
tools use verified stable upstream releases when native candidates are too old
or absent. Existing incompatible/unknown sources and conflicting user configs
fail with preservation diagnostics. Resolve sources explicitly before rerunning.
`dfa-update-system` (daily/weekly, or `--force`) also refreshes managed editor
releases. Shared plugins, socket lookup, reveal hooks, and default-harness fallback
remain shared. Dev setup links the launcher, reveal-hook command, updater, and
shared command library without replacing user commands. See
[editor sources and validation limits](PACKAGES.md#neovim-and-tmux-distro-slice).

---

## Choose your path

| Situation | What to run |
|-----------|-------------|
| **Brand-new Arch install** | archinstall → `./post_install.sh` (chains straight into bootstrap) |
| **Existing machine / other PC** | `bash scripts/sync.sh` |
| **Day-to-day package updates** | `bash scripts/update-system.sh` (Arch: guarded `pacman` + AUR; Ubuntu: APT) |
| **Just re-link configs** | `bash scripts/link-dotfiles.sh` |
| **One tool only** | `bash scripts/setup-<tool>.sh` |

Paths use `$HOME` — different usernames on other machines are fine.

### Day-to-day updates (preferred)

```bash
dfa-daily                         # dfa-update-repos + dfa-migrate + dfa-update-system + dfa-sync-extensions + dfa-sync-skills + dfa-sync-rules + dfa-sync-harness-agents (edit ~/.local/bin/dfa-daily)
                              # if dfa-update-repos pulls new dotfiles-arch commits, runs dfa-sync-dotfiles and restarts once
dfa-weekly                        # dfa-daily + forced updates + orphan preview + native NinjaOne health check
dfa-install-ninjaone             # standalone, work machines: hidden vendor URL prompt (native Ubuntu DEB / Arch repackaging)
dfa-update-ninjaone              # weekly health/repair for owned installs; IT-managed agents checked read-only
dfa-uninstall-ninjaone           # terminal + type remove; Ubuntu retains SentinelOne unless --remove-sentinelone is separately confirmed
dfa-sync-sources add /path/to/repo # optional: extra rules/skills/extensions repo; then dfa-sync-extensions && dfa-sync-skills && dfa-sync-rules
dfa-update-system                 # after link-dotfiles; or:
bash scripts/update-system.sh
bash scripts/update-system.sh --yes        # native updates; Arch requires a clean AUR scan
bash scripts/update-system.sh --scan-only  # Arch AUR scan; Ubuntu diagnostic only
bash scripts/update-system.sh --force      # bypass the 1-day cooldown
dfa-update-repos                  # parallel git pull --ff-only under ~/repos (MAX_PARALLEL=8)
dfa-migrate                       # apply pending schema migrations (--dry-run to preview)
dfa-remove-orphans                # native candidates only (no sudo/removal)
dfa-remove-orphans --remove       # terminal confirmation: type remove; then native transaction prompt
```

Arch updates use pacman, then an AUR PKGBUILD/dependency IoC scan, then `yay -Sua`.
Unattended Arch updates add a temporary native transaction hook that refuses
package removals/replacements while retaining configured hooks. Ubuntu uses
`apt-get update --error-on=any` then `apt-get upgrade --with-new-pkgs --no-remove`;
holds, pins, configured sources, and automatic security updates remain intact.
Neither path performs a release upgrade. Held/deferred packages are reported by
the native manager; they do not imply app parity or completed full upgrades.

The 24h cooldown and `--force` override are shared. Successful native/AUR steps
atomically write `~/.config/dotfiles-arch/.last_system_upgrade_<arch|ubuntu>`.
Until the first successful Arch update, all three existing `.last_pacman_update`,
`.last_pacman_upgrade`, and `.last_yay_update` stamps are read without rewriting
or deleting them. Missing, invalid, or future stamps require a retry. Failed
steps do not stamp success and survive daily/weekly and Arch bootstrap/sync summaries.
Sync always upgrades; bootstrap retains its cooldown.
The npm CLI step updates only launchers owned by the selected global npm package;
vendor/native or shadowing launchers are preserved and reported as source conflicts.

Cleanup defaults to a read-only native plan (`pacman -Qtdq` plus recursive removal
preview on Arch; APT autoremove simulation on Ubuntu). Weekly only previews;
`--yes` and `--force` never authorize removal. Use `dfa-remove-orphans --remove`
separately in a terminal and review managed software before confirming.
See [maintenance sources, policies, and validation limits](PACKAGES.md#maintenance-distro-slice).

---

## New install

### 1. Install Arch (archinstall)

Target schema matches **archinstall 4.4** (`user_configuration.json`).

1. Get network (WiFi: `iwctl` — see [NOTES.md](NOTES.md)).
2. Prepare `user_configuration.json` before install:
   ```shell
   ./prepare-archinstall.sh
   ```
   Guided: pick your disk from a live listing (this **wipes** it), enter a hostname, confirm the detected graphics driver. `--dry-run` previews the changes. Doesn't touch `user_credentials.json` — set auth/LUKS password there yourself, or hand-edit `user_configuration.json` directly if you skip the script.
3. Run archinstall with the config (USB or config URL — details in [NOTES.md](NOTES.md)).

Layout: **Btrfs + LUKS + Snapper**, GNOME + GDM, PipeWire, NetworkManager.

### 2. Post-install (minimal)

After first reboot, from a clone of this repo:

```bash
./post_install.sh
```

Enables multilib, updates packages, optional NVIDIA (`setup-nvidia.sh`), and installs Kitty + build basics. Then hands off directly into bootstrap (step 3) — no separate command needed.

### 3. Bootstrap (full workstation)

Runs automatically at the end of `post_install.sh`. To re-run it later on its own (it's idempotent):

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

### Pi configuration

Shared Pi configuration lives under [`pi/`](pi/) and is linked into `~/.pi/agent` by
`link-dotfiles.sh` (settings and model configuration). Pi extensions, including the
[remote control](pi/extensions/), are synced from `pi/extensions/` plus
configured extra sources by `dfa-sync-extensions`. See the [remote-control operator
guide](pi/extensions/remote-control/README.md) for setup and operation. Pi's machine-local
credentials and
runtime model catalog — `auth.json` and `models-store.json` — remain local; the model store is
not symlinked because Pi updates its timestamps. Global `AGENTS.md` is generated from the
repository's synced rules and linked by `sync-rules.sh`.

---

## Profiles

Profiles are **additive** — select any combination on one machine (e.g. work + devcontainer).

| Profile | Extra setup | Default browser (Super+B) |
|---------|-------------|---------------------------|
| **work** | Zoom, Slack, Chrome | Chrome (when work is selected) |
| **personal** | Steam, Discord, Firefox, Mullvad VPN (Arch / Ubuntu 26.04 sources in `PACKAGES.md`) | Firefox (when personal is selected and work is not; selected Snap/DEB desktop identity) |
| **devcontainer** | just, mkcert, OpenVPN 3, DNS for `~test`, inotify watches | — (no browser change) |

Everything else in the stack is shared (including Docker and `gh` used by the devcontainer host setup, and all three agent CLIs — Claude Code, Codex, and opencode).

---

## What's installed

### Shared stack

| Area | Tools |
|------|--------|
| **Shell / CLI** | bash, Starship, zoxide, eza, fzf, ripgrep, fd, bat, git-delta, jq, htop, btop, ncdu, duf, tldr, fastfetch, shellcheck, stow, wl-clipboard, xsel |
| **Terminal** | Kitty (Catppuccin Mocha) |
| **Multiplexer** | tmux |
| **Editors / AI** | Neovim (LazyVim-style), Claude Code (`claude`), Codex (`codex`), Ollama (local models — NVIDIA or Vulkan GPU only), Zed, [Orca](https://www.onorca.dev/) (`stably-orca` / `orca-ide`, Arch scanned AUR / Ubuntu self-updating AppImage) |
| **Git** | git, lazygit (`lzg`), GitHub CLI (`gh`) |
| **Languages** | Node (NVM LTS), Python, Rust (rustup), Go, PHP + Composer + Laravel, Ruby + Rails |
| **Containers** | Docker, Compose, Buildx, lazydocker (`lzd`), minikube, kubectl, k9s |
| **Apps** | TablePlus, Postman, Spotify, Obsidian, ZSA Keymapp (Moonlander) |
| **Fonts** | Adwaita Sans/Mono (GNOME UI), Noto + Liberation fallbacks, Meslo / Ubuntu / Fira Code / JetBrains Mono / Hack Nerd Fonts |
| **Desktop** | GNOME + Pop Shell (tiling off by default), Dash to Panel (top bar), No Overview, AppIndicator, GPaste, Papirus + Catppuccin GTK |

Standalone `scripts/setup-{python,rust,golang,php,ruby}.sh` now select native
packages for Arch / Ubuntu 26.04, check capabilities, and report source
conflicts. Rust defaults and user Composer/gem paths are preserved. See the
[language source/update matrix](PACKAGES.md#shared-language-sources-and-update-owners)
for prerequisites and manual toolchain/gem updates. New installs use the latest
available from their selected sources, without language version floors.
Use `python3 -m venv .venv`
for project Python packages. Ubuntu full bootstrap remains guarded; installation
and update behavior has only read-only/static validation.

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

Only an explicit saved `INSTALL_NVIDIA=true` or `bash scripts/setup-nvidia.sh --install`
permits a new installation. `--yes` keeps the saved choice; hardware detection
does not opt in. Existing native, manual and work-managed stacks are retained.
New Arch installs use `nvidia-open-dkms` (Turing+); Ubuntu 26.04 uses its native
hardware recommendation and prefers signed modules for the running kernel.
Reboot/Secure Boot/MOK activation can remain pending; setup does not replace,
unload or force-load drivers. See [GPU sources and update owners](PACKAGES.md#gpu-sources-capability-gates-and-update-owners).

`bash scripts/setup-ollama.sh` requires working CUDA or a physical Vulkan 1.2+
GPU. Arch uses native GPU packages. Ubuntu prefers a compatible native package
if available, otherwise a verified official archive with a user service;
`dfa-update-system` owns archive refreshes. Existing source/service conflicts
remain untouched. No models are downloaded by setup, and GPU inference/runtime
is unverified. Archive service status/logs: `systemctl --user status ollama` /
`journalctl --user -u ollama`; native installs use the system service.

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

Agents: `dev --tmux <dir> --agent <harness>` (`claude`, `codex`, or `opencode`) starts that CLI in the split pane. Without `--agent`, `dev --tmux` uses `DEFAULT_HARNESS` — set during `setup-dev.sh` (auto-picked if only one harness CLI is installed, asked with a numbered list if several are) — and falls back gracefully at runtime if that saved default's CLI has gone stale (silently to the sole installed harness, an interactive prompt if several remain, a plain shell if none are installed). Claude's and Codex's file edits automatically reveal themselves in the Neovim pane (loaded into the edit window like a nvim-tree click, or focused/reloaded in place if already open) via the `nvim-reveal-edit` hook installed by `setup-claude.sh`/`setup-codex.sh`. `dfa-sync-extensions`, `dfa-sync-skills`, and `dfa-sync-rules` keep shared Pi extensions, skills, and always-apply rules available to detected Codex installations under `$CODEX_HOME` (default `~/.codex`).

**Zed:** a Terminal Thread (Agent Panel → "+" → Terminal, or `Ctrl+Alt+T` — see `config/zed/keymap.json`) runs `zed-agent-init`, which starts the same `DEFAULT_HARNESS` CLI as `dev --tmux` (with the same stale-default fallback) — no separate reveal hook is needed since the agent runs inside the same Zed window as the editor, so Zed's own file watcher picks up its edits.

### Shell (highlights)

| Command | What it does |
|---------|----------------|
| `dev [dir]` | Open the project in Zed |
| `stably-orca`, `orca-ide` | Launch Orca; Arch scanned AUR / Ubuntu self-updating AppImage; standalone `bash scripts/setup-orca.sh` |
| `dev --tmux [dir]` | tmux session instead: `code` window (`nvim .` + agent pane, focus on agent), `console` shell window, optional `lazygit` (git repo; `--force` for non-git; `--agent claude\|codex` to pick the agent) |
| `v` / `vim` | Neovim |
| `vimcheat` | Neovim cheat sheet |
| `lzg` / `lzd` | lazygit / lazydocker |
| `z` / `zi` | Smart cd (zoxide) |
| `r` / `dfa-repos` | fzf-pick a repo under `~/repos` and cd into it |
| `dfa` | Command picker grouped into Routine, AI, Projects, Dotfiles, and System; search `AI` or `sources` to find AI configuration tools (`dfa list` prints the groups) |
| `dfa sync-sources` | Interactive manager for local rules, skills, and extensions sources: add, remove, reorder, and apply changes. Removing a source keeps its files; `dfa sync-sources list` lists without prompts |
| `pbcopy` / `pbpaste` | Wayland clipboard in/out |
| `mvup` / `mvdown` / `mvst` | Mullvad connect / disconnect / status |
| `check` | Syntax + shellcheck the repo scripts |
| `orphans` | Remove orphaned pacman packages |
| `rebind-window-push` | Keep Super+Ctrl+Arrows on Pop Shell (tiled) or Mutter (floating) |
| `gs` `ga` `gc` `gp` `gpush` … | Git aliases (diffs paged through delta) |
| `welcome` | Shell cheat sheet |
| `aliases` | Aliases + key bindings |
| `packages` | What every installed package is for ([PACKAGES.md](PACKAGES.md)) |
| `claude` | Claude Code CLI |
| `codex` | Codex CLI |
| `ollama run <model>` | Chat with a local model |
| `reload` | Reload `~/.bashrc` |

Readline (Tab menu-complete, history search, word jumps): see `welcome` or `~/.inputrc`.
fzf adds **Ctrl+R** (history), **Ctrl+T** (files), and **Alt+C** (cd into a subdirectory).

Kitty: **Ctrl+Shift+=/-** font size, **Ctrl+Shift+Backspace** reset, **Ctrl+Shift+F** scrollback pager, **Ctrl+Shift+E** URL hints.

Neovim: leader is **Space** — full map in `~/.nvim-cheatsheet.md` (`vimcheat`).

---

## Day-to-day workflow

1. **Terminal** — Super+Return (Kitty).
2. **Project** — `cd` / `z` into a repo, then `dev` for Zed (`dev --tmux` for tmux + Neovim), or run `claude` / `codex` as needed.
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
├── CLAUDE.md              ← shared architecture and agent guidance
├── AGENTS.md              ← symlink to CLAUDE.md for other agents
├── .cursor/rules/         ← repo conventions for AI agents
├── prepare-archinstall.sh ← guided disk/hostname/gfx_driver prep, before archinstall
├── post_install.sh        ← minimal post-archinstall (chains into bootstrap.sh)
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
│   └── .local/bin/        # dfa-daily, dfa-weekly, dfa-migrate, dfa-update-repos, dfa-sync-dotfiles, dfa-sync-skills, dfa-sync-rules, dfa-sync-sources, dfa-sync-harness-agents, dfa-update-system, dfa-refresh-audio, …
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
| [AGENTS.md](AGENTS.md) | Shared agent guidance (symlink to `CLAUDE.md`) |
| `welcome` (in shell) | Alias and tmux quick reference |
| `vimcheat` | Neovim keybindings |

### Agent council

Use `/grill-me` or `/grill-with-docs` for a lower-cost interview without the council.
Use `/advise-me` or `/advise-with-docs` for automatic council recommendations;
the `with-docs` variants capture resolved terms and accepted decisions in glossary/ADRs.
Use `agent-council` directly for a standalone debate. Only relevant roles compare evidence and
tradeoffs: PM owns long-term vision, BA product/domain web research, TPM interoperability
and integration research, Architect scalable/maintainable design, and Engineer
existing code and standards. Human choices stay yours. Simple questions use compact
lenses, disputes use independent agents with a fixed debate budget. Accepted Q/A can feed
`/to-spec` and `/to-tickets`; `/bro` explains the answer simply. These are agent
skill invocations, not shell commands. Install through `dfa-sync-skills`.
BA and TPM check existing research first; project councils save reusable findings
in `docs/market-research/` by default unless explicitly told not to store research.
See [examples and limits](skills/mikedelafuente/agent-council/references/examples.md).

Personal workflows: `/ask-mike` chooses an entrypoint; `/council-handoff spec|tickets`
carries accepted decisions into Matt's original workflow; `/build-with-ponytail`
adds simplicity guidance and combined final `/review-changes`. Skills are grouped
by source under `skills/{mattpocock,ponytail,mikedelafuente}` and installed under
their original names. Dotfiles-arch has final skill priority; duplicate replacement requires the losing
source to allow overwrites (`dfa-sync-sources add <path> --overwritable true`).
Protected duplicates stop sync before links change. See [imports and update review](skills/README.md).

`dfa-sync-sources` manager option **5** toggles skill overwrites for an existing
source. It displays the current setting; changes apply on the next skill sync.

### Shared agent config in cloud checkouts

Keep this repository as a second checkout (for example `/workspace/dotfiles-arch`)
next to the working project. Add this command to the existing cloud setup script,
keeping the project's existing setup commands:

```bash
bash /workspace/dotfiles-arch/scripts/install-cloud-agent-config.sh --home "$HOME"
```

Requires Bash, Python 3.8+, and ordinary shell utilities (`awk`, `mktemp`, `whoami`);
no Arch packages, sudo, network calls, desktop config, or agent CLI installation.
The checkout must remain available during the task. The installer derives source
paths from its own checkout and links complete skill folders into
`<home>/.agents/skills`; no laptop paths or Trellis skill copies are used.
It reads only this checkout, not the laptop's extra sync sources.

Shared `rules/` files with `alwaysApply: true` are flattened through the existing
rule field/body readers into a managed block in `$CODEX_HOME/AGENTS.md` (default
`<home>/.codex/AGENTS.md`). Conditional rules and `rules/README.md` are excluded.
This is the shared global baseline used by workstation rule sync; the repository's
root `AGENTS.md`/`CLAUDE.md` describes Arch setup and is not a project-agnostic
baseline. Neither that file nor `.cursor/rules/` is copied into the working project.
Existing text outside the managed block and project `AGENTS.md` files stay intact.
Reruns update the block and prune only removed skills owned by this checkout.
Unrelated skill collisions, global AGENTS symlinks, malformed managed blocks, and
nonempty global `AGENTS.override.md` fail without replacing user content.

Codex's documented user skill location is `$HOME/.agents/skills`; global
instructions load before project instructions, with nearer project instructions
resolving conflicts. [Skill discovery](https://learn.chatgpt.com/docs/build-skills)
and [AGENTS discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
Start a fresh cloud task after the saved setup is published; an existing task or
browser refresh does not establish that the setup ran. Verify the actual runtime's
catalog and loaded global/project instruction sources; local filesystem tests do
not prove cloud discovery. If the environment changes `HOME`/`CODEX_HOME` between
setup and task launch, use the task's actual home values for installation.

Local regression check: `python3 tests/test_cloud_agent_config.py`.

Desktop IDE standalone setup supports Arch and Ubuntu 26.04:
`bash scripts/setup-zed.sh` and `bash scripts/setup-orca.sh`. `dev` accepts either
Zed command (`zeditor` or `zed`); shared settings and default-harness terminal
threads remain intact. Ubuntu favors true self-updates: the official Zed user
archive and Orca AppImage, with in-app updates enabled. Arch retains native/scanned
AUR update ownership; existing Ubuntu Orca DEBs refresh through `dfa-update-system`
because their in-app update messages only notify. See [PACKAGES.md](PACKAGES.md#desktop-ide-sources-and-update-owners-arch--ubuntu-2604)
for sources, conflicts and unverified runtime paths. Zed needs Vulkan and 1.18+;
setup preserves unrelated desktop/MIME defaults and reports source/config conflicts.
Full Ubuntu bootstrap/sync remains guarded while remaining slices are converted.

Shared appearance: `bash scripts/setup-fonts.sh` installs required font families
on Arch and Ubuntu 26.04. Native fonts/themes use normal distro updates; pinned
font/GTK/Papirus/bat data uses maintainer-reviewed versions applied by setup/full
sync. User assets are preserved on conflicts. See [PACKAGES.md](PACKAGES.md#shared-appearance-sources-and-update-owners)
for sources, ownership, and unverified desktop behavior.
