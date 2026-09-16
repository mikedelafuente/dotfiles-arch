# Install Notes

Start here for the big picture: [README.md](README.md). After time away: [REFRESHER.md](REFRESHER.md).

Target ISO: [archlinux-2026.07.01](https://fastly.mirror.pkgbuild.com/iso/2026.07.01/) (ships **archinstall 4.4**).
`user_configuration.json` is written for that schema (`bootloader_config`, `pacman_config`, zram `swap` object, nested `disk_encryption`).

## WiFi (before archinstall)

The live ISO needs network access before you can run `archinstall` or fetch configs. On WiFi:

```shell
# List interfaces (look for wlan0, wlp*, etc.)
ip link

# Enable the interface if it is down
ip link set wlan0 up

# Connect with iwctl (default on the Arch ISO)
iwctl
```

Inside `iwctl`:

```shell
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "YourSSID"
exit
```

Confirm connectivity:

```shell
ping -c 3 archlinux.org
```

If DHCP did not assign an address:

```shell
dhcpcd wlan0
# or
systemctl start iwd
iwctl station wlan0 connect "YourSSID"
```

Wired Ethernet usually works without setup (`dhcpcd` / NetworkManager on the ISO). Prefer Ethernet when available.

## Config on USB

To save the config to persistent storage, mount a USB drive:

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb;
```

You can use that same medium to replicate the installation from the USB stick:

```shell
mkdir -p /mnt/usb && mount /dev/sda1 /mnt/usb && archinstall --config /mnt/usb/dotfiles-arch/user_configuration.json --creds /mnt/usb/dotfiles-arch/user_credentials.json;
```

Alternately, you can leverage the presaved file on http://archconfig.weekendproject.app/

```shell
archinstall --config-url http://archconfig.weekendproject.app/
```

**Step zero, before running archinstall:** from this repo on the USB (or a clone on the live ISO), run the guided prep script:

```shell
./prepare-archinstall.sh
# ./prepare-archinstall.sh --dry-run   # preview the changes first
```

It lists your block devices and lets you pick the install target, prompts for a hostname, and detects (or lets you override) the graphics driver — then writes all three straight into `user_configuration.json`. It never reads, writes, or references `user_credentials.json`.

You still need to set by hand:

- Authentication (including the LUKS encryption password in `user_credentials.json`)

Or, without the script, hand-edit `user_configuration.json` yourself:

- Disk device path (`disk_config.device_modifications[0].device`)
- Hostname
- `gfx_driver` (see [GPU / NVIDIA](#gpu--nvidia) below)

## Disk layout (preconfigured)

`user_configuration.json` uses archinstall's default single-disk layout with:

- **Filesystem**: btrfs on the root partition, FAT32 EFI at `/boot` (1 GiB)
- **Subvolumes**: `@` (/), `@home` (/home), `@log` (/var/log), `@pkg` (/var/cache/pacman/pkg)
- **Snapshots**: Snapper
- **Encryption**: LUKS on the root/btrfs partition

Before installing, set `device` to your target disk (e.g. `/dev/nvme0n1` or `/dev/sda`). Confirm with `lsblk` / `dmesg`. The layout wipes the selected disk.

You can get some extra information about what drives were inserted using `dmesg`

You can unmount via `umount /mnt/usb`

## GPU / NVIDIA

`user_configuration.json` currently sets archinstall `gfx_driver` to **NVIDIA open** (Turing+). `./prepare-archinstall.sh` detects the GPU vendor and proposes the matching value (falling back to `All open-source` if it can't tell); confirm or override it there. Without the script, change `gfx_driver` by hand before install, or pick the right driver in the archinstall UI.

After install, NVIDIA packages are **not** forced:

- `post_install.sh` / `scripts/setup-nvidia.sh` detect existing NVIDIA packages (from archinstall) and/or an NVIDIA GPU
- You are prompted; the choice is saved as `INSTALL_NVIDIA` in `~/.config/dotfiles-arch/.dotfiles_bootstrap_config`
- Bootstrap and sync reuse that preference (`false` skips installing nvidia-open-dkms)

## After install

GNOME + GDM are installed by archinstall. For multilib, optional NVIDIA, Kitty, and base tools:

```shell
./post_install.sh
```

This hands off directly into bootstrap for the rest of the tooling (any arguments you
pass to `post_install.sh` are forwarded to it) — no separate command needed. You will be
prompted for profiles (multi-select; any combination):

- **work** — shared stack + Zoom + Slack + Chrome
- **personal** — shared stack + Steam + Discord + Firefox + Mullvad
- **devcontainer** — host tools for the platform sandbox (just, mkcert, openvpn3, `~test` DNS, …)

Example for a work laptop that also runs the platform sandbox:

```shell
bash scripts/bootstrap.sh --profile work,devcontainer
```

Everything else (Kitty, Claude, Codex, Ollama, tmux, languages, containers, Spotify, Obsidian, etc.) is shared. Mullvad is personal-only; Super+B prefers Chrome when **work** is selected.

```shell
bash scripts/bootstrap.sh
```

## AUR / package updates (security)

Day-to-day upgrades should use the guarded updater (not raw `yay -Syu`):

```bash
bash scripts/update-system.sh
# bash scripts/update-system.sh --yes
# bash scripts/update-system.sh --scan-only
```

This runs `pacman -Syu`, scans pending AUR PKGBUILDs **and AUR-only dependencies** for known supply-chain IoCs (e.g. Atomic Arch: `atomic-lockfile`, `js-digest`, `curl|sh` in build scripts), then upgrades AUR packages. Yay itself is IoC-scanned before first `makepkg`. This is a **known-IoC gate**, not a full PKGBUILD audit.

Bootstrap always sets `DOTFILES_AUR_ASSUME_YES=true` for non-interactive AUR installs after a clean scan. Sync sets that only with `--yes`.

Official `core`/`extra`/`multilib` packages are signed; AUR is community PKGBUILDs — treat as lower trust.

## Syncing an existing machine (drift / other PCs)

After big repo changes, bring a machine up to date without reinstalling Arch:

```shell
cd /path/to/dotfiles-arch
bash scripts/sync.sh
```

That will:

1. Resolve profiles + NVIDIA (keeps saved values silently; use `--prompt` to re-ask)
2. `git pull --ff-only` (if this is a git clone)
3. Guarded system upgrade (`pacman` + AUR IoC scan + `yay`) **every run**
4. Re-run the setup scripts (idempotent installs for Kitty, tmux, Claude, Codex, …)
5. Relink dotfiles
6. Optionally remove obsolete packages (`herdr-bin`, `ghostty`, `alacritty`, Hyprland stack, Copilot CLI) and stale configs

Useful flags:

```shell
bash scripts/sync.sh --profile work
bash scripts/sync.sh --profile work,devcontainer
bash scripts/sync.sh --profile personal
bash scripts/sync.sh --prompt            # re-ask profiles / NVIDIA
bash scripts/sync.sh --cleanup           # remove obsolete packages
bash scripts/sync.sh --skip-bootstrap    # skip setup-*.sh (still upgrades + links)
bash scripts/sync.sh --yes --profile work,devcontainer --cleanup
```

If no profiles are saved yet, sync prompts you to choose one or more of **work**, **personal**, **devcontainer** (with `--yes`, you must pass `--profile`).

Do this on each machine that should match the repo. Fresh installs still use `bootstrap.sh`. For day-to-day package-only updates, prefer `dfa-update-system`.

Paths use `$HOME` / `$USER_HOME_DIR` so different usernames on other machines work without edits.

### Open-weight models for Matt Pocock skills

**Skill exists:** `.pi/agent/skills/evaluate-models/SKILL.md` - query leaderboards and match models to skills.

Short version: skills are model-agnostic, but reasoning-heavy ones benefit from top-tier coders. See full SKILL.md for methodology. Current state on this machine (Sept 2026):

| Skill | Best overall model | Best budget model | **Best available** |
|-------|------------------|-------------------|-------------------|
| ask-matt | Claude Sonnet 5 | Qwen3-Coder-30B | **DeepSeek V4 Flash** (current Pi model) |
| grill-me | Kimi K2.5 | DeepSeek V3.2-Reasoner | DeepSeek V4 Flash |
| grill-with-docs | Qwen3-Coder-480B | GLM 5 | DeepSeek V4 Flash |
| wayfinder | Qwen3-Coder-480B | Kimi K2.5 | DeepSeek V4 Flash |
| to-spec | Qwen3-Coder-480B | DeepSeek V3.2 | DeepSeek V4 Flash |
| to-tickets | GLM 5 | DeepSeek V3.2 | DeepSeek V4 Flash |
| implement | Qwen3-Coder-480B | Qwen3-Coder-30B | dolphin3 (ollama) |
| tdd | Qwen3-Coder-30B | DeepSeek V3.2 | **dolphin3** (ollama - local) |
| diagnosing-bugs | DeepSeek V3.2-Reasoner | GLM 5 | DeepSeek V4 Flash |
| code-review | GLM 5 | Kimi K2.5 | DeepSeek V4 Flash |
| codebase-design | Qwen3-Coder-480B | GLM 5 | DeepSeek V4 Flash |
| domain-modeling | Qwen3-Coder-480B | Qwen3-Coder-30B | dolphin3 |
| research | DeepSeek V3.2-Reasoner | Qwen3-Coder-30B | DeepSeek V4 Flash |
| prototype | Qwen3-Coder-30B | Gemma 3 27B | dolphin3 |
| wizard | Any 30B+ | Gemma 3 12B | dolphin3 |

**General work (non-coding tasks):**

| Task | Best model | Budget | What's available |
|------|------------|--------|----------------|
| General chat | **Kimi K2.5** | GLM 5 | **DeepSeek V4 Flash** (fast) |
| Writing emails | GPT-4o / Claude Sonnet | GLM 5 | DeepSeek V4 Flash |
| Research / reading | **DeepSeek V3.2-Reasoner** | Qwen3-Coder-30B | DeepSeek V4 Flash |
| Summarization | Gemini 2.0 Flash | Llama 3.3 70B | DeepSeek V4 Flash |
| Translation | Qwen3 / GLM 5 | Nous Hermes 3 | DeepSeek V4 Flash |
| Data analysis | Qwen3-Coder-480B | DeepSeek V3.2 | dolphin3 |
| Image understanding | GPT-4o / Kimi 2.5 | Llama 3.2 Vision | (none local) |
| Creative writing | Claude Sonnet | Gemma 2 27B | dolphin3 |
| Brainstorming | Kimi K2.5 | DeepSeek V3.2 | DeepSeek V4 Flash |

**Current availability:**
- **Pi**: DeepSeek V4 Flash (via OpenRouter)
- **Ollama local**: dolphin3:latest
- **Claude Code**: Sonnet/Opus via Anthropic API
- **Codex**: GPT-4.1-mini or full-family via GitHub Models

**Leaderboard sources:** [swe-bench.github.io](https://swe-bench.github.io/) (Verified Open), [livebench.ai](https://livebench.ai/), [lmarena.ai](https://lmarena.ai/)

**Provider cost matrix (per 1M tokens):**

| Model | Claude Code | OpenAI | OpenRouter | GitHub/Codex |
|-------|-------------|--------|------------|--------------|
| Claude 3.5 Sonnet 5 | $3/$15 | — | $3/$15 | — |
| GPT-4o | — | $2.50/$10 | $2.50/$10 | $0* |
| GPT-4o-mini | — | $0.15/$0.60 | $0.15/$0.60 | $0* |
| DeepSeek V3.2 | — | — | **$0.09/$0.35** | — |
| DeepSeek V3.2-R | — | — | **$0.14/$0.55** | — |
| Qwen3-Coder-480B | — | — | ~$1.20/$3.60 | — |
| Qwen3-Coder-30B | — | — | **$0.10/$0.30** | — |
| Kimi K2.5 | — | — | ~$2/$8 | — |
| GLM 5 | — | — | ~$0.50/$1.50 | — |

*GitHub Models free tier has rate limits (~150/min, ~50/day for GPT-4o)

## One-time: v1 -> v2 command rename cleanup

The day-to-day commands (`morning`, `sync-dotfiles`, `repos`, etc.) were renamed under a
`dfa-` prefix. `link-dotfiles.sh` only creates symlinks for files currently in the repo —
it never removes ones whose source got renamed away — so a machine set up before this
rename is left with the old commands as dangling `~/.local/bin` symlinks, alongside none
of the new `dfa-*` ones. Run this once per existing machine, then reload your shell:

```shell
bash migrations/v1-to-v2-migration.sh
source ~/.bashrc
```

Safe to re-run; a machine that's already been migrated (or never had the old names) is a
no-op.

## GNOME overview at login

GNOME has no built-in “skip Activities at startup” setting. This repo uses:

1. **`no-overview@fthx`** (`gnome-shell-extension-no-overview`) — primary fix
2. **`hide-gnome-overview` autostart** — portable `$HOME`-based fallback if the overview still flashes

Both are intentional; either alone is usually enough.
