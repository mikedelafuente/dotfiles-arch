# Packages

## Installed DFA copies

Managed configuration, helpers, rules, skills and Pi extensions now use stable installed copies at
`~/.local/share/workstation/config`. Moving the checkout preserves runtime paths. `dfa-deploy update`
obtains shared changes, stages/merges, validates and activates one generation; conflicts preserve
live files and return failure. `dfa-deploy deploy` snapshots local edits without committing or fetching.
Direct sync and setup commands use those snapshots for testing. `dfa-deploy source` identifies the shared edit destination.
Use `dfa-deploy capture <artifact>` for one selected source improvement,
`dfa-deploy override <artifact> <file>` for a persistent local override,
`dfa-deploy rebind <checkout>` after a source move, and `dfa-deploy rollback` / `recover`
for recovery. See [deployment policy and dependency inventory](docs/deployment.md).

Deployment uses existing Git (`merge-file`), Bash syntax checks and native Python 3.11+
(`python` on Arch, `python3` on Ubuntu); no Stow/AI/model/network merge service is used.
Native/app acquisition and update owners keep the contracts below.


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
| `fzf` | Fuzzy finder | Ctrl-R history, Ctrl-T files, Alt-C cd, grouped `dfa` command picker, `dfa-repos`, `r` |
| `ripgrep` | Fast recursive search | `rg`; also used by AUR IoC scans |
| `fd` | Fast `find` replacement | `fd`; backs `FZF_DEFAULT_COMMAND` |
| `bat` | Syntax-highlighted pager | `welcome`, `packages`, `vimcheat`, `MANPAGER` |
| `glow` | Terminal Markdown renderer | `glow`, `md` |
| `htop` | Interactive process viewer | `htop` |
| `btop` | Richer resource monitor | `btop` |
| `ncdu` | Disk usage explorer | `ncdu` |
| `duf` | Friendly `df` | `duf` |
| `tree` | Directory tree | `tree` |
| `jq` | JSON processor | `jq` |
| `net-tools` | Legacy net utilities | `ports` (`netstat`), `ifconfig` |
| `iw` | Wireless device config/query (nl80211) | `iw list`, `iw dev` |
| `stow` | Symlink farm manager | manual dotfile experiments |
| `shellcheck` | Shell static analysis | `check` / `dfa-check-dotfiles`, CI |
| `github-cli` | GitHub from the terminal | `gh`; also the git credential helper |
| `tldr` | Example-first man pages | `tldr <cmd>` |
| `fastfetch` | System summary | `fastfetch` |
| `zoxide` | Directory jumping that learns | `z`, `zi`, `zq` |
| `bash-completion` | Bash command completion | Tab |
| `less` | Plain pager fallback | `less`, Git pager fallback |
| `util-linux` (Arch) / `bsdextrautils` (Ubuntu) | Strip man-page formatting | `col` in `MANPAGER` |
| `linux-firmware-intel` | Intel firmware (only on Intel hardware) | — |

### Shared shell and core CLI distro slice

Implemented for [#143](https://github.com/mikedelafuente/dotfiles-arch/issues/143).
Standalone `setup-essentials.sh`, `setup-bash.sh`, `setup-git.sh`,
`setup-github-cli.sh`, and `setup-node.sh` support rolling Arch and Ubuntu 26.04
on x86_64/amd64. The shared bootstrap/sync entrypoints support both distros; runtime validation remains unverified.

| App / command | Arch package | Ubuntu package/source | Required version/capability |
|----------------|--------------|-----------------------|-----------------------------|
| Git / `git` | `git` | `git` | 2.35+ (`zdiff3`) |
| Delta / `delta` | `git-delta` | [git-delta](https://packages.ubuntu.com/resolute/git-delta) | 0.16+; shared pager settings |
| Transfers / `curl`, `wget` | `curl`, `wget` | `curl`, `wget` | Native HTTPS/TLS support |
| Clipboard / `xsel`, `wl-copy`, `wl-paste` | `xsel`, `wl-clipboard` | `xsel`, `wl-clipboard` | XWayland / Wayland clients |
| Listing / `eza` | `eza` | `eza` | 0.18+ (`--icons=auto`) |
| Prompt / `starship` | `starship` | [starship](https://packages.ubuntu.com/resolute/starship) | 1.22+; shared palette/modules |
| Finder / `fzf` | `fzf` | [fzf](https://packages.ubuntu.com/resolute/fzf) | 0.48+ (`--bash`) |
| Search / `rg` | `ripgrep` | `ripgrep` | 13+ |
| Finder / `fd` | `fd` | [fd-find](https://packages.ubuntu.com/resolute/fd-find), `fdfind` | 8+; user executable link to `/usr/bin/fdfind` |
| Pager / `bat` | `bat` | [bat](https://packages.ubuntu.com/resolute/bat), `batcat` | 0.23+ and configured Catppuccin Mocha theme; user executable link to `/usr/bin/batcat` |
| Markdown / `glow`, `md` | `glow` | [Charm's official APT repository](https://github.com/charmbracelet/glow#installation), `glow` | 1+ |
| Resource tools | `htop`, `ncdu`, `btop`, `duf` | Same explicit package names | Native commands |
| Utilities | `tree`, `jq`, `net-tools`, `iw`, `stow`, `shellcheck` | Same explicit package names | `tree`, `jq`, `netstat`, `iw`, `stow`, `shellcheck` |
| GitHub / `gh` | `github-cli` | `gh` | 2+; credential helper remains `/usr/bin/gh` |
| Examples / `tldr` | `tldr` | [tealdeer](https://packages.ubuntu.com/resolute/tealdeer) | Native `tldr`; page cache refreshed with `tldr --update` |
| Summary / `fastfetch` | `fastfetch` | [fastfetch](https://packages.ubuntu.com/resolute/fastfetch) | Native command |
| Navigation / `zoxide` | `zoxide` | `zoxide` | Native Bash integration |
| Bash / completion / pager | `bash`, `bash-completion`, `less` | Same explicit package names | Bash 4+; Tab and pager fallback |
| Man-page filter / `col` | `util-linux` | `bsdextrautils` | Required by shared `MANPAGER` |
| SSH / `ssh`, `ssh-keygen`, `ssh-agent`, `ssh-add` | `openssh` | `openssh-client` | Ed25519 support; existing keys retained |
| Git TUI / `lazygit`, `lzg` | `lazygit` | [lazygit](https://packages.ubuntu.com/lazygit) | 0.40+ |
| Source prerequisites | `curl`, `coreutils`, `ca-certificates`, `gnupg`, `tar` | Same explicit package names | HTTPS, SHA-256, GPG key inspection, archive extraction |
| NVM / `nvm` | Verified upstream archive | Same [NVM v0.40.3 archive](https://github.com/nvm-sh/nvm/tree/v0.40.3) | 0.40.3+; `~/.config/nvm` |
| Node / `node`, `npm` | NVM's verified upstream Node binaries | Same NVM owner | Node 22+; fresh installs select current LTS |

**Update owners:** every native row uses pacman on Arch and APT on Ubuntu through
`dfa-update-system` (daily/weekly). Ubuntu's Main/Universe sources must already be
enabled; unavailable candidates or failed acquisition fail without source fallback.
Firmware remains Arch's Intel-gated package, or Ubuntu's existing native/IT owner.
No AUR scan/install behavior changes. Glow is the only vendor APT exception here;
APT also owns its updates. Package signature verification stays with pacman/APT.

Glow stages Charm's HTTPS key and verifies primary fingerprint
`ED927B38BE981E53CA09153D03BBF595D4DFD35C` before registering
`/etc/apt/sources.list.d/dfa-charm.list` with `signed-by=/etc/apt/keyrings/dfa-charm.gpg`.
An exact existing upstream `charm.list` / `charm.gpg` recipe with that fingerprint
is retained verbatim. Unknown/duplicate registrations, key changes, shadowing
launchers, or unmanaged binaries fail and remain untouched; no global trust is added.
Key rotation needs an explicitly reviewed fingerprint update.

`setup-node.sh` owns the pinned NVM files: a maintainer bumps version and archive
SHA-256 together, then users rerun standalone setup. It stages/checks the whole
archive before extracting only `nvm.sh`, `nvm-exec`, and `bash_completion` and
updating older NVM files. Node/npm updates belong to user-level NVM:
`nvm install --lts` verifies upstream Node checksums; select a new default explicitly
with `nvm alias default 'lts/*'`. Setup retains compatible defaults, reports broken
or Node <22 defaults, and refuses root/sudo, foreign Node sources, non-user-owned
NVM files, and npm prefixes outside NVM. npm globals keep their existing daily
`dfa-update-npm-clis` owner. No distro Node, root npm, or rc-file append is introduced.
Legacy `~/.nvm` moves only into an absent/empty target; nonempty conflicts are retained.

**Commands/config:** `setup-bash.sh` links shared `.bashrc`, `.inputrc`, `.profile`,
welcome/package/Neovim reference files, and `starship.toml`; essentials links bat's
config and checks the theme/cache; Git links shared XDG config and keeps identity
in the real machine-local `.gitconfig`. Without arguments, Git keeps machine-local
identity first, then uses saved identity through `load_bootstrap_config`; explicit
name/email arguments update it. Saved profiles/preferences are not rewritten.
Existing unrelated config files, directory symlinks, and command links are conflicts:
back them up or resolve them explicitly before rerunning. `fd`/`bat` links live in
`~/.local/bin`, usable by subprocesses when that directory is on PATH; shared Bash
adds it before selecting `MANPAGER`. No aliases substitute for these commands.
Paths derive from the checkout and `USER_HOME_DIR`, independent of username/location.

**Validation:** `python3 tests/test_core_cli_decisions.py` checks supplied mapping,
version, ownership, and link facts in temporary state with forbidden-command guards.
`bash scripts/check.sh` checks Bash syntax and ShellCheck. No setup, package update,
source registration, service, driver, GNOME, networked test, or VM workflow runs.
Installation/update behavior, repository trust at runtime, NVM migration/downloads,
shell startup, Git authentication, and actual CLI/config compatibility on either
distro remain **unverified**. Package metadata and upstream recipes establish
source feasibility, not successful workstation installation.

## Shell, terminal, and editor

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| `bash` | `setup-bash.sh` | Login shell | `~/.bashrc`, `~/.inputrc` |
| `kitty` | `setup-kitty.sh` | GPU terminal (Catppuccin Mocha) | Super+Return, Ctrl+Shift+F scrollback, Ctrl+Shift+E URL hints |
| `tmux` | `setup-dev.sh` | Terminal multiplexer | `tmux`, `dev --tmux` |
| `neovim` | `setup-neovim.sh` | Editor | `v`, `vim`, `nvim`, `dev --tmux` |
| `gcc`, `make` | `setup-neovim.sh` | Build Treesitter parsers / native plugins | — |
| `python-pynvim` / Ubuntu `python3-pynvim` | `setup-neovim.sh` | Neovim Python provider | — |
| `tree-sitter-cli` | `setup-neovim.sh` | Treesitter grammars | `:TSUpdate` |
| `lazygit` | `setup-git.sh` | Git TUI | `lzg` |
| `lazydocker` | `setup-docker.sh` / `setup-dev.sh` | Docker TUI; Arch Extra / verified Ubuntu release exception | `lzd` |

### Neovim and tmux distro slice

Implemented for [#144](https://github.com/mikedelafuente/dotfiles-arch/issues/144).
Standalone `setup-neovim.sh` and `setup-dev.sh` support rolling Arch and Ubuntu
26.04 on amd64/x86_64. Shared bootstrap/sync supports both distros.

| App / commands | Arch source | Ubuntu 26.04 source | Minimum / update owner |
|----------------|-------------|---------------------|------------------------|
| Neovim / `nvim`, `v`, `vim`, `dev --tmux` | Compatible native `neovim` preferred | Native 0.11.6 is insufficient; missing installs use [official stable archives](https://github.com/neovim/neovim-releases/releases) | **0.12.0+**; native package owner or managed upstream refresh via `dfa-update-system` |
| Treesitter / `tree-sitter`, `:TSUpdate` | Compatible native `tree-sitter-cli` preferred | Native 0.25.9 is insufficient; missing installs use [official stable releases](https://github.com/tree-sitter/tree-sitter/releases) | **0.26.1+**; native package owner or managed upstream refresh via `dfa-update-system`; never npm |
| tmux / `tmux`, `dev --tmux` | Native `tmux` | Native `tmux` | **3.2+**; native package owner |
| Git TUI / `lazygit`, `lzg` | Native `lazygit` | Native Universe `lazygit` | **0.40+**; native package owner and existing core CLI ownership checks |
| Container TUI / `lazydocker`, `lzd` | [Arch Extra `lazydocker`](https://archlinux.org/packages/extra/x86_64/lazydocker/) | Compatible native candidate if available, otherwise [verified official releases](https://github.com/jesseduffield/lazydocker/releases) | **0.20+**; native package owner or managed upstream refresh via `dfa-update-system` |
| Build/archive/TLS helpers | `gcc`, `make`, `tar`, `gzip`, `unzip`, `ca-certificates` | Same native names | Native package updates; parser/native-plugin builds and verified downloads |
| Python provider / Mason tools | `python`, `python-pynvim`, `python-pip` | `python3`, `python3-pynvim`, `python3-pip`, `python3-venv` | Native package updates; Ubuntu virtual environments respect externally managed system Python |
| Search/Git/hooks/clipboard | `fd`, `ripgrep`, `git`, `curl`, `jq`, `wl-clipboard`, `xsel` | `fd-find` plus executable `fd` link; remaining names match | Existing core CLI/native package owner; `jq` supports reveal-hook payloads |
| Node / LSP runtimes | User NVM | User NVM | Run `setup-node.sh` first; Node LTS and agent updates retain existing owners |

Evidence checked 2026-10-08: [Ubuntu Neovim 0.11.6](https://packages.ubuntu.com/resolute/amd64/neovim),
[tree-sitter 0.25.9](https://packages.ubuntu.com/resolute/amd64/tree-sitter-cli),
[tmux 3.6a](https://packages.ubuntu.com/resolute/tmux), and
[lazygit 0.57.0](https://packages.ubuntu.com/lazygit).
Official GitHub release metadata identified stable Neovim **0.12.5**, tree-sitter
**0.27.1**, and lazydocker **0.25.2**, with amd64 asset SHA-256 digests. They satisfy
the numeric floors in the [pinned Treesitter contract](https://github.com/nvim-treesitter/nvim-treesitter/blob/8b98b4470eb326f1c7b50dae79f8c963568e5720/README.md);
runtime compatibility remains unverified. Selection queries the host's configured
native candidate metadata instead of hardcoding these facts. Unreadable metadata
fails; refresh native indexes before setup. No PPA, foreign APT suite, plugin
downgrade, npm generator, or fallback after failed acquisition is added.

Compatible native tools stay native. Old existing native tools must be updated by
their owner or explicitly removed/reselected by the operator. Unknown/shadowing
launchers, user commands, a native package beside a managed tree, and unrelated
directory/link ownership fail without source migration or duplicate installation.
Arch updates retain pacman/AUR scanning; dev setup uses official Extra lazydocker
rather than initiating an AUR install. User config conflicts fail before setup
writes. Existing per-file repo links, identical copies, and additional user files
are retained. Plugins and `lazy-lock.json` remain unchanged.

Managed releases live at
`USER_HOME_DIR/.local/share/dotfiles-arch/editor-tools/<command>/<version>`, with
`.dfa-source` recording the upstream owner and `current` selecting the release.
Commands link from `USER_HOME_DIR/.local/bin`, which must already be on PATH.
`dfa-update-system` refreshes only recognized managed trees after native/AUR
updates, before success stamps, including Arch's no-yay/no-foreign-packages path.
Daily/weekly sequencing and cooldown are unchanged; `dfa-update-system --force`
explicitly refreshes. GitHub latest-stable metadata must supply the exact official
asset URL and SHA-256 digest. Downloads, safe archive extraction, and executable
version checks finish in staging before `current` switches atomically. Neovim's
binary and runtime switch together; old releases are retained. Metadata, checksum,
archive, version, or ownership failure returns nonzero and bypasses success stamps.
Digest verification provides integrity against official HTTPS metadata, not an
additional publisher signature. Expected asset naming/API availability and Python
archive data-filter support are required; failures preserve the selected source.

Standalone setup links Neovim config per file and `.tmux.conf`. No preferences,
schema versions, command names, plugin configuration, or default-harness fallback
change. `dev --tmux` checks actual stable nvim/tree-sitter/tmux versions before
killing its old session, quotes the socket command for Bash, and passes the session
name as a child-shell argument in Kitty. Reveal hooks still share socket naming,
`jq`, and `nvim --server --remote-expr`; existing Claude/Codex hook commands remain
valid. Docker Engine/Compose/Buildx and hook installation remain separate slices.
Dev setup also links `dev`, `nvim-reveal-edit`, `dfa-update-system`, and their
shared `dotfiles-arch-lib.sh` into `USER_HOME_DIR/.local/bin`; it preflights all
four for user-file/unrelated-link conflicts. This enables the launcher, existing
hook command, and explicit refresh on a fresh Ubuntu host without full dotfile
linking. It does not install agent CLIs or register new harness hooks.

**Validation:** `python3 tests/test_editor_decisions.py` checks supplied distro,
version, source/update-owner, release-metadata, and temporary config-tree facts.
Forbidden command guards prevent network/package-manager/sudo/service/desktop or
live editor/tmux calls. Bash syntax/ShellCheck and static review cover setup,
staging, ownership, launch/socket/hooks, dispatch, and failure/stamp ordering.
**Unverified:** native install/update behavior, real archive extraction/replacement,
downloaded binary ABI/runtime loading, plugins/Mason/LSP/provider/parser builds,
tmux/Kitty launch, socket/RPC/reveal hooks, clipboard/fonts, and lazydocker against
Docker. No OS-changing workflows, networked tests, or VM provisioning were run.

### Kitty distro slice

| Host | App source / package | Update owner |
|------|----------------------|--------------|
| Rolling Arch, x86_64/amd64 | [Arch Extra](https://archlinux.org/packages/extra/x86_64/kitty/), `kitty` | pacman, through the existing guarded system updater |
| Ubuntu 26.04, x86_64/amd64 | [Ubuntu Universe](https://packages.ubuntu.com/resolute/kitty), `kitty` | APT through existing configured sources, via `dfa-update-system` / daily / weekly |

`bash scripts/setup-kitty.sh` is a converted Ubuntu setup path. No vendor
repository, archive, AUR-to-APT translation, or fallback source is added. Missing
Universe/package candidates and APT errors fail setup. Package status uses
`pacman -Q` or dpkg's actual `installed` status with an `ok` error flag (including
held packages, without changing their selection). A native installation
must select `/usr/bin/kitty` (including `/bin` or symlink aliases resolving there)
on PATH. Unmanaged/shadowing launchers are preserved and reported as conflicts;
setup never installs a second copy to fix them.

The recipe supports Kitty **0.26+** with the existing shared settings (see the
[upstream 0.26 config definitions](https://github.com/kovidgoyal/kitty/blob/v0.26.0/kitty/options/definition.py)).
Older/broken installations fail with an update-owner diagnostic and are retained.
Setup links `kitty.conf` and `themes/mocha.conf` under `USER_HOME_DIR/.config/kitty`.
Existing links to these repo files and identical legacy regular copies are kept;
other files, directories, and unrelated/broken symlinks at those targets are
preserved and reported before package installation. No bootstrap preferences,
schema state, or command names change. Font setup remains a separate Arch-only
entrypoint; absent Nerd Fonts use Kitty's normal font fallback.

Validation for this slice is limited to supplied-data host decisions, Bash
syntax, ShellCheck, and static review. At the maintainer's request, no app tests
or setup/update/cleanup/service/desktop/driver workflows are executed. Native
package installation/failure behavior, Kitty config loading/rendering, fonts,
and KDE/GNOME terminal preference changes on either distro remain **unverified**.
See the final Ubuntu source/update audit below for all selected owners.

### Maintenance distro slice

Implemented for [#142](https://github.com/mikedelafuente/dotfiles-arch/issues/142).

| Installed apps / host | App source | Update owner |
|-----------------------|------------|--------------|
| Native system packages, including Kitty / Arch | Existing official pacman repositories | `dfa-update-system`: pacman, then guarded AUR updates |
| AUR apps / Arch | Existing AUR recipes, including their AUR dependencies | `yay -Sua` after an IoC scan; query/scanner/metadata failures fail closed |
| Native packages, including Kitty / Ubuntu 26.04 | Existing configured Ubuntu and vendor APT repositories | `dfa-update-system`: APT refresh and upgrade with new dependencies permitted, removals refused |
| Existing npm-installed Claude / Codex / Pi / either host | User-level npm packages through NVM | `dfa-update-npm-clis` daily step verifies global package and resolved launcher ownership; no root npm |
| Recognized user-native Claude / either host | Official user-native launcher into `USER_HOME_DIR/.local/share/claude/versions/<version>` | `dfa-update-npm-clis` runs `claude update` as the user, independently of NVM/npm; native background updates retain user/IT policy; visible DISABLE_UPDATES is deferred |
| NinjaOne / Arch | Existing opt-in repackaged vendor DEB | Agent self-updater plus existing weekly health check |
| NinjaOne / Ubuntu | Opt-in vendor native DEB; existing IT-selected installations retained | Agent/patcher self-updater; weekly owned-agent repair or read-only IT-managed health check |

No package or software source is installed by this slice. It adds no vendor
repository, signing key, source fallback, app migration, or duplicate installation.
APT keeps existing holds/pins and source priorities; source conflicts remain for
the source owner to resolve. Standalone DEBs/archives use their explicit verified refresh owners listed below;
APT alone does not update them. Recognized native Claude uses its own updater; other
shadowing or non-npm agent launchers are preserved and reported as source
conflicts, returning nonzero without adding an npm duplicate. Native Claude
recognition requires an executable regular version file in the official user
layout; redirected directories and unknown paths are rejected. Native-update
failure remains a failure even if NVM/npm is unavailable. See
[Claude's documented native layout and update owner](https://code.claude.com/docs/en/setup#update-claude-code).
Recognition is checked with supplied temporary files; updater dispatch is
statically inspected without executing an update workflow as a test.
Ubuntu automatic security timers, blacklists, and service
configuration are untouched (see [Ubuntu automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/)).

`dfa-daily` keeps its step order and aggregates failures. `dfa-weekly` still runs
daily first, forces the native update, previews orphan/removal candidates, then
handles NinjaOne (IT-managed installations receive read-only health checks). User-only sync steps are allowed on
Ubuntu; shared bootstrap/sync and historical dotfile migrations use the same
failure-preserving entrypoints. Daily auto-resync failures stay in its summary.
Arch bootstrap/sync now preserve shared update/setup failures in their exit status.

Commands/config: `dfa-remove-orphans`/`orphans` now preview; `--remove` requires
a terminal and typing `remove`, followed by the native transaction prompt.
`--yes`/`--force` alone cannot remove packages; `--dry-run` always previews.
Arch uses native recursive removal planning; Ubuntu uses APT autoremove simulation
and retains config files during cleanup. Review managed packages before approval.
The [APT manual](https://manpages.ubuntu.com/manpages/resolute/man8/apt-get.8.html)
documents holds, `--no-remove`, and simulation; the [Arch hooks manual](https://man.archlinux.org/man/alpm-hooks.5.en)
documents the temporary removal-blocking hook used for unattended updates.

Successful system updates atomically stamp `.last_system_upgrade_arch` or
`.last_system_upgrade_ubuntu` under `~/.config/dotfiles-arch`. Existing Arch stamps
are read in place until first success and retained afterward; no schema bump,
command rename, or bootstrap preference change is required. Each manager/query/scan
failure returns nonzero before stamping; policy deferrals remain visible.

Validation: `python3 tests/test_maintenance_decisions.py` checks supplied distro,
timestamp, and removal-approval facts with temporary state and forbidden-command
guards. It executes only read-only library decisions. Bash syntax/ShellCheck and
static inspection cover dispatch, update failures/stamps, AUR dependencies, and
daily/weekly aggregate status. Actual pacman/yay/APT queries, transactions,
hook forwarding/execution, sudo, removals, held/deferred updates, concurrency with
security timers, NinjaOne, and full workstation behavior remain **unverified**.
No OS-changing workflows, networked tests, services, GNOME/driver changes, or VMs
are run for validation.

## Fonts — `setup-fonts.sh`

| Package | Purpose |
|---------|---------|
| `adwaita-fonts` | GNOME 48+ UI font (Adwaita Sans / Mono) |
| `noto-fonts` | Broad Unicode coverage |
| `noto-fonts-emoji` | Color emoji (Super+. picker, chat apps) |
| `ttf-liberation` | Metric-compatible Arial/Times substitutes |
| `ttf-jetbrains-mono-nerd` | Kitty / Neovim terminal font with icons |
| `ttf-meslo-nerd`, `ttf-ubuntu-nerd`, `ttf-firacode-nerd`, `ttf-hack-nerd` | Alternate Nerd Fonts |

### Shared appearance sources and update owners

Implemented for [#150](https://github.com/mikedelafuente/dotfiles-arch/issues/150).
`setup-fonts.sh` supports rolling Arch and Ubuntu 26.04; GNOME's appearance
acquisition uses `ensure_gnome_appearance` from `scripts/appearance-lib.sh`.
Desktop settings/extension compatibility remains a separate slice.

| Asset / required name | Arch source | Ubuntu 26.04 source | Update owner |
|-----------------------|-------------|--------------------|--------------|
| `Adwaita Sans` | `adwaita-fonts` | [fonts-adwaita-sans](https://packages.ubuntu.com/resolute/fonts-adwaita-sans) | pacman / APT |
| `Adwaita Mono` | `adwaita-fonts` | [GNOME Adwaita Fonts 49.0](https://download.gnome.org/sources/adwaita-fonts/49/) verified archive, only unpatched Mono TTFs | pacman / maintainer pin + font setup/sync |
| `Noto Sans`, `Noto Serif`, `Noto Sans Mono` | `noto-fonts` | [fonts-noto-core](https://packages.ubuntu.com/resolute/fonts-noto-core), `fonts-noto-mono` | pacman / APT |
| `Noto Color Emoji` | `noto-fonts-emoji` | `fonts-noto-color-emoji` | pacman / APT |
| `Liberation Sans`, `Liberation Serif`, `Liberation Mono` | `ttf-liberation` | [fonts-liberation](https://packages.ubuntu.com/resolute/fonts-liberation) | pacman / APT |
| `JetBrainsMono Nerd Font`, `MesloLGS Nerd Font`, `Ubuntu Nerd Font`, `FiraCode Nerd Font`, `Hack Nerd Font` | Existing `ttf-*-nerd` rows above | [Nerd Fonts v3.5.1](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.5.1): JetBrainsMono, Meslo, Ubuntu, FiraCode, Hack archives | pacman / maintainer pin + font setup/sync |
| `catppuccin-mocha-lavender-standard+default` | Scanned `catppuccin-gtk-theme-mocha` AUR | [Catppuccin GTK v1.0.3](https://github.com/catppuccin/gtk/releases/tag/v1.0.3) exact Mocha/Lavender/Standard/default ZIP | guarded AUR / maintainer pin + GNOME setup/sync |
| `Papirus-Dark`, `cat-mocha-lavender` folders | `papirus-icon-theme` + scanned `papirus-folders-catppuccin-git` | [papirus-icon-theme](https://packages.ubuntu.com/resolute/papirus-icon-theme) + [Catppuccin folder assets](https://github.com/catppuccin/papirus-folders/tree/f83671d17ea67e335b34f8028a7e6d78bca735d7), private user copy of native Papirus/Papirus-Dark | pacman + guarded AUR / APT for base, maintainer pin + GNOME setup/sync for overlay |
| `Catppuccin Mocha` for bat | Prefer built-in theme | Prefer built-in theme; otherwise [pinned upstream tmTheme](https://github.com/catppuccin/bat/blob/6810349b28055dce54076712fc05fc68da4b8ec0/themes/Catppuccin%20Mocha.tmTheme) on either distro | native package, or maintainer pin + essentials setup/sync |
| Font/data staging prerequisites | `fontconfig`, `curl`, `ca-certificates`, `python` | `fontconfig`, `curl`, `ca-certificates`, `python3`, `xz-utils` | native package owner |

Ubuntu's `fonts-adwaita` metapackage contains documentation and depends on Sans;
it does **not** ship the unpatched Mono font. Regular `fonts-jetbrains-mono` is
also insufficient: shared Kitty/GNOME configuration requires the Nerd Font family.
All downloaded artifacts have fixed SHA-256 values in `appearance-lib.sh`.
Nerd Font hashes come from the official release asset metadata; GNOME publishes
its archive checksum. Catppuccin ZIP/archive/tmTheme hashes were recorded from
HTTPS upstream artifacts on 2026-10-09, providing a reviewed pin rather than a
publisher signature. Archive contents are data only, staged with traversal/special
file rejection; no upstream installer or build script executes.

Downloads live in immutable, marked directories under
`~/.local/share/dotfiles-arch/appearance/`; only recipe-owned public symlinks can
be repointed. Fonts link from `~/.local/share/fonts/dfa-*`, GTK from `~/.themes`,
and bat from `~/.config/bat/themes`. Ubuntu's Papirus overlay links from
`~/.local/share/icons/Papirus{,-Dark}`; its base is recopied when the native package
version changes on the next GNOME setup/sync. APT-owned `/usr/share/icons` is
never recolored on Ubuntu. Existing real files, unrelated links, linked ancestor
directories, and unmarked recipe destinations fail and remain preserved.
Fonts already supplied by another source fail before duplicate downloaded families
are installed; retain that owner or explicitly migrate. A compatible existing bat
theme is retained; a user-provided theme keeps its manual user update owner.
Old marked versions remain available; no automatic asset cleanup is introduced.

`dfa-daily`/`dfa-weekly` update native/AUR assets through `dfa-update-system`.
They do not independently refresh pinned downloads or regenerate the Ubuntu
Papirus overlay. The maintainer reviews new artifact versions and hashes together;
`dfa-sync-dotfiles` (or the respective font/essentials/GNOME setup) applies pins.
A daily pull that invokes full sync inherits that behavior when the full distro
setup is enabled. There is no claim that APT updates downloaded fonts/themes.

**Maintenance limit:** [Catppuccin GTK is archived](https://github.com/catppuccin/gtk)
since June 2024. The existing selected theme remains frozen at v1.0.3; future GTK
compatibility repairs require an explicit maintainer decision. Setup does not
inject GTK4/libadwaita CSS or alter GDM. These applications can retain their own
appearance despite the GTK theme preference.

**Validation:** the supplied-fact regression check
`tests/test_appearance_decisions.py` covers package selection, exact family names,
and owned/unowned links plus safe data-only archive extraction; it was written
but **not run**, per the execution limit.
Bash syntax/ShellCheck were run directly on changed shell files. Upstream artifact
layouts and distro metadata were inspected read-only. Font rendering, fontconfig
resolution, bat cache loading, GTK/Libadwaita behavior, GNOME theme discovery,
Papirus inheritance/recoloring, downloads and installation on real machines remain
**unverified**. Post-link `refresh_font_cache` remains in its existing position;
font setup also refreshes before checking exact installed family names.

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
| `gnome-shell-extension-pop-shell-git` (AUR) | GNOME 50 tiling; GNOME 51 selects a reviewed source pin instead | Super+Y, Super+G, Super+Escape when compatible |
| `gnome-shell-extension-no-overview` (AUR) | Skip the overview at login | — |
| `papirus-icon-theme` | Icon theme | — |
| `papirus-folders-catppuccin-git` (AUR) | Catppuccin folder colors | `papirus-folders` |
| `catppuccin-gtk-theme-mocha` (AUR) | GTK theme | — |

### Shared GNOME sources and update owners

`setup-gnome.sh` detects GNOME with the native package backend and validates every
required extension's installed `metadata.json` against the actual shell major.
Unsupported metadata or missing required schemas/keys fails setup, except the
explicitly accepted Pop Shell gap above GNOME 51. The old global version-validation bypass is reset on both
distros. User extensions shadowing native recipes, unowned upstream targets, and
duplicate sources are preserved and reported as conflicts requiring explicit migration.

**GNOME 51 Pop Shell:** [upstream compatibility patch](https://github.com/pop-os/shell/pull/1830)
at [commit `31f04c3`](https://github.com/pop-os/shell/tree/31f04c32d2fbf92afcd3dd5194ac16755008bae2)
declares GNOME 45–51 and replaces the removed `St.BoxLayout.vertical` API.
The author reports GNOME 51.0 testing; a user also reports success on CachyOS
51.0 Wayland. Setup compiles the SHA-256-verified archive with native TypeScript;
local verification covers compilation and schemas, not a live desktop session.
On Arch the managed user pin supersedes the known AUR system copy without
removing its package/files. Unknown system copies and unrelated user extensions
still fail preflight. Pin changes require a reviewed revision/checksum update.
GNOME 50 retains its existing source. Above GNOME 51, the accepted Pop-only gap
keeps native moves while Super+Y/G/Escape remain unavailable; other required
extension failures still fail setup.

| Feature | Arch source | Ubuntu 26.04 source | Update owner |
|---|---|---|---|
| Tweaks, base extensions, dconf inspector, emoji picker | `gnome-tweaks`, `gnome-shell-extensions`, `dconf-editor`, `gnome-characters` | Same native package names | pacman / APT |
| Pop Shell tiling (GNOME 50–51 support; accepted skip above 51) | GNOME 50: scanned `gnome-shell-extension-pop-shell-git` AUR; GNOME 51: verified `31f04c3` pin, native `typescript`/`glib2` | [System76 source commit `7898b65`](https://github.com/pop-os/shell/tree/7898b65c20735057faf0797f8ed056704ca55f0d), declares GNOME 45–50; GNOME 51 selects `31f04c3`; verified SHA-256 archive, compiled with native `node-typescript` and `libglib2.0-bin` | Scanned AUR / maintainer-reviewed pin, applied by setup/sync |
| No Overview at login | Scanned `gnome-shell-extension-no-overview` AUR | [Upstream commit `9246cc6`](https://github.com/fthx/no-overview/tree/9246cc6efba01729a3e19ca898018ab5e98a26b9), declares GNOME 48–51; verified SHA-256 archive | Scanned AUR / maintainer-reviewed pin, applied by setup/sync |
| AppIndicator tray | `gnome-shell-extension-appindicator`, UUID `appindicatorsupport@rgcjonas.gmail.com` | [`gnome-shell-ubuntu-extensions`](https://packages.ubuntu.com/resolute/gnome-shell-ubuntu-extensions), UUID `ubuntu-appindicators@ubuntu.com` | pacman / APT |
| Dash to Panel | `gnome-shell-extension-dash-to-panel` | [Upstream v74](https://github.com/home-sweet-gnome/dash-to-panel/releases/tag/v74), declares GNOME 46–51; ZIP checked against GitHub's SHA-256 release digest; absent from the resolute native catalog | pacman / maintainer-reviewed pin, applied by setup/sync |
| GPaste clipboard/history | `gpaste` | [`gpaste-2`](https://packages.ubuntu.com/resolute/gpaste-2), [`gnome-shell-extension-gpaste`](https://packages.ubuntu.com/resolute/gnome-shell-extension-gpaste), `gir1.2-gpaste-2`; native 45.3-5 includes GNOME 50 support patch | pacman / APT |
| Balanced/performance profile provider | `power-profiles-daemon` | Same native package; preserve installed TLP, tuned/tuned-ppd or System76 providers and masked/inactive services | pacman / APT; external policies retain their owner |
| Theme/icons/fonts | See shared appearance recipes above | Same shared appearance recipes | Native package manager / maintainer pins as documented above |

Pinned extension archives on both distros live under `~/.local/share/dotfiles-arch/gnome/` with
marked version directories and protected links into the standard per-user
GNOME extension directory. Pin changes require a reviewed source/checksum change;
repo updates followed by setup/sync apply them. Native extensions and the GPaste
daemon follow ordinary `dfa-update-system` updates. No downloaded installer,
Pop `local-install`/shortcut-reset script, forced compatibility patch, or PPA is used.
Pop's separate launcher is disabled: Super+Space retains GNOME's app grid.

On Ubuntu, setup disables the conflicting Ubuntu Dock, Tiling Assistant and
Desktop Icons NG, plus the alternate upstream AppIndicator UUID. It retains
unrelated extensions including Canonical security/prompting extensions.
Extension schemas are read from their installed local or system directories;
`rebind-window-push` also supports the local Pop schema. Above GNOME 51 it applies
native shortcuts without reading/writing Pop settings and exits rather than
watching tiling. On GNOME 50–51, a missing required Pop schema/key still fails.
GPaste 51 removes the cosmetic `max-displayed-history-size` key; setup reports
and skips that optional setting, retaining the required 100-item history and Super+V.

Audio/lid/USB policy files keep the existing paths and mark ownership. Foreign
local or runtime overrides and symlinks defer the relevant policy with a warning.
The legacy exact audio-disable file is recognized as ours; laptops restore
`power_save=1`, desktops request `0`. Lid/USB changes apply on reboot/device
add/change; setup does not restart logind or trigger all USB devices.
`dfa-refresh-audio` requires active, loaded WirePlumber, PipeWire and
PipeWire Pulse user services; missing/masked/inactive services fail before any
restart. `--status` only queries `wpctl` and propagates its failure.

Read-only vendor/package metadata establishes source feasibility. Installation,
TypeScript compilation, extension loading, GSettings, panel/clipboard/tiling,
services, audio, lid, USB wake and hardware behavior remain unverified.
`tests/test_gnome_decisions.py` supplies version, extension-list, policy/service
and archive facts in temporary state; it was written and left unrun under the
validation restriction. Only direct Bash syntax/ShellCheck checks were executed.

## Languages and runtimes

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| Arch `python`, `python-pip`, `python-pynvim`; Ubuntu `python3`, `python3-pip`, `python3-venv`, `python3-pynvim`, `python3-dev` | `setup-python.sh` | Interpreter, pip, venv/ensurepip, Neovim provider, native extension headers | `py`, `pip`, `serve`, `jsonpp` |
| Arch `go`, `gopls`; Ubuntu `golang-go`, `gopls` | `setup-golang.sh` | Go compiler, standard library, language server | `go`, `gopls` |
| Arch/native retained `rustup`; new Ubuntu verified user `rustup-init` | `setup-rust.sh` | User Rust toolchain manager; compatible existing distro Rust is retained | `cargo`, `rustc`, `rustup` |
| Arch `ruby`, `sqlite`, `base-devel`; Ubuntu `ruby`, `ruby-dev`, `sqlite3`, `libsqlite3-dev`, `build-essential`, `libyaml-dev` | `setup-ruby.sh` | Ruby/RubyGems, Ruby headers, Rails database, native gem compilation and YAML headers | `ruby`, `gem`, `bundle`, `rails` |
| Arch `php`, `php-gd`, `php-intl`, `php-sqlite`, `php-pgsql`, `composer`; Ubuntu `php-cli`, `php-curl`, `php-gd`, `php-intl`, `php-mbstring`, `php-xml`, `php-mysql`, `php-sqlite3`, `php-pgsql`; verified user Composer PHAR or retained native `composer` | `setup-php.sh` | PHP CLI, HTTP/image/Unicode/XML extensions, MySQL/SQLite/PostgreSQL drivers, Composer and user Laravel installer | `php`, `composer`, `laravel` |
| Arch `base-devel`, `openssl`, `zlib`, `libffi`, `libyaml`, `pkgconf`, `sqlite`; Ubuntu `build-essential`, `libssl-dev`, `zlib1g-dev`, `libffi-dev`, `libyaml-dev`, `pkg-config`, `sqlite3`, `libsqlite3-dev` | All five language setups | C/C++ compiler/linker/make, TLS/compression/FFI/YAML headers, library discovery, SQLite CLI/headers for native builds | `cc`, `make`, `pkg-config`, `sqlite3` |
| NVM + Node LTS (not pacman) | `setup-node.sh` | Node via NVM at `~/.config/nvm` | `nvm`, `node`, `npm` |
| Claude Code (Arch user npm; Ubuntu verified native; existing owners retained) | `setup-claude.sh` | Claude Code CLI | `claude` |
| Codex CLI (user-level npm, `@openai/codex`) | `setup-codex.sh` | OpenAI Codex CLI | `codex` |
| Arch `chatgpt-desktop` (AUR) / Ubuntu official `chatgpt` APT | `setup-codex.sh` | ChatGPT desktop app (repackaged official binary) | `chatgpt` |
| `opencode` | `setup-opencode.sh` | AI coding agent CLI | `opencode` |
| Arch `ollama-cuda` / `ollama-vulkan`; Ubuntu compatible native `ollama` or verified upstream archive (GPU-gated) | `setup-ollama.sh` | Local model server; working CUDA preferred, otherwise a physical Vulkan 1.2+ GPU. No CPU-only installation; existing flavors preserved. Sources/services/update owners below | `ollama` |

### Shared language sources and update owners

The five standalone language setups support rolling Arch and Ubuntu 26.04 amd64.
They retain the native backend for Python/Go/PHP/Ruby and compatible existing
managers. New Ubuntu rustup and Composer use verified user self-updating sources;
no root-owned user installs or unverified remote-shell installers are introduced.
Shared bootstrap/sync supports these recipes on both distros.
New installs use unversioned native language packages, latest stable Rust via
rustup, stable user Composer PHAR on Ubuntu, and unpinned user gems/Composer dependencies. There are no repository-imposed language version floors. Existing
installations and explicit user toolchain selections retain their update owners.

| Component | Source / retained installation | Update owner | Compatibility / configuration |
| --- | --- | --- | --- |
| Python | Native distro packages above | `dfa-update-system`; project dependencies use the project's venv/pip | Import pip, venv, ensurepip and pynvim; native-owned `pip3`. No system pip installs or externally-managed override. |
| Go / gopls | Native packages above | `dfa-update-system` | Compiler tool and standard-library directories must exist. Go's optional automatic toolchain selection is left unchanged; stable versions with build experiment suffixes are accepted. |
| rustup binary | Arch native `rustup`; Ubuntu verified official user `rustup-init` for new installs; compatible native/user managers retained | Native binary: `dfa-update-system`; user binary: manual `rustup self update` | Rustup proxies must share the manager's file identity; Arch provider aliases do not count as separate installed toolchains. Existing user `CARGO_HOME`/`RUSTUP_HOME` remain user-owned; no pipe-to-shell installer. |
| Rust / Cargo | User toolchains via rustup, or existing distro Rust/Cargo | Rustup toolchains: manual `rustup update`; distro toolchain: `dfa-update-system` | Latest stable is initialized only with no selected default/toolchain; existing pinned, beta/nightly defaults and `RUSTUP_TOOLCHAIN` are retained. No distro rustup self-update. |
| PHP / existing native Composer | Native distro packages above | `dfa-update-system` | Laravel-required builtins/extensions and GD/Intl/MySQL/SQLite/PostgreSQL are checked. Arch enables exact missing directives in shared `/etc/php/php.ini`; Ubuntu enables missing modules with `phpenmod -v <major.minor> -s cli`, using `/etc/php/<major.minor>/cli/{php.ini,conf.d}` derived from the installed PHP version and leaving web server SAPIs unchanged. |
| New Ubuntu Composer | Official SHA384-verified PHP installer, stable user PHAR | Manual `composer self-update`; genuine binary replacement | PHP native runtime retained; writable user PHAR under `~/.local/share/dotfiles-arch/composer`, stable by default. Existing native Composer stays native. |
| Laravel installer | Composer global package in the existing user Composer home/bin-dir | Manual `composer global update laravel/installer` | Preserve `COMPOSER_HOME`/global bin-dir; verify the installer command. Shell PATH includes XDG/explicit Composer homes and legacy `~/.composer/vendor/bin`; custom bin-dir must already be on PATH. |
| Ruby / native headers | Native distro packages above | `dfa-update-system` | RubyGems, OpenSSL and Psych must work; NVM Node is required for the existing Rails JS workflow. |
| Bundler / Rails | User gems (`gem install --user-install`) or compatible existing native commands | User gems: manual `gem update --user-install <user-gem> --no-document` (`bundler` or `rails` only when user-owned); native gems: `dfa-update-system` | Use RubyGems' actual `Gem.user_dir`, not a hardcoded Ruby ABI. PATH covers XDG `gem/ruby/*/bin` and legacy `~/.gem/ruby/*/bin`; verify `bundle` and `rails`, even when a gem is listed. Never `sudo gem` or `gem update --system`. |

Manual toolchain/gem/Composer updates retain the existing opt-in workflow; daily
native updates do not claim to refresh them. All package, rustup, gem and Composer
mutation failures exit nonzero before setup completion; these setups write no
successful-update stamps. Native update stamps retain the shared backend's failure
contract. User tooling is rejected when run as root. Unknown/shadowing launchers,
unowned alternatives, unreadable command versions, custom PHP config overrides, and
linked/root-owned/outside-home user state are reported and retained. A native runtime
without the selected package identity (for example a version-only PHP package without
`php-cli`) needs source resolution before setup rather than acquiring another runtime.
Custom conflicting `GEM_HOME`/`GEM_PATH` is reported instead of rewritten.

Primary-source evidence: Ubuntu packages
[rustup](https://packages.ubuntu.com/resolute/rustup),
[golang-go](https://packages.ubuntu.com/resolute/golang-go),
[gopls](https://packages.ubuntu.com/resolute/gopls),
[Ruby](https://packages.ubuntu.com/resolute/ruby),
[Ruby headers](https://packages.ubuntu.com/resolute/ruby-dev), and
[PHP CLI](https://packages.ubuntu.com/resolute/php8.5-cli).
[Laravel's PHP/extension requirements](https://laravel.com/framework/docs/12.x/deployment),
[Rails' Ruby requirements](https://guides.rubyonrails.org/getting_started.html),
[RubyGems user paths](https://guides.rubygems.org/faqs/),
[Composer globals](https://getcomposer.org/doc/03-cli.md#global), and
[Arch's PHP file layout](https://archlinux.org/packages/extra/x86_64/php/files/)
support the configuration choices. Actual dependency compatibility is checked by
the runtimes/package tools without imposing a separate language version policy.

**Validation:** `python3 tests/test_language_decisions.py` uses supplied package,
version, ownership, PHP module/config-path and Rust default facts, with temporary
user state and forbidden-command guards. Bash syntax/ShellCheck and static inspection
cover package/config writes and failure paths. Installation, repeated setup on real
hosts, compiler/native-gem builds, venv creation, live module loading, proxy packaging,
networked toolchain/gem/Composer updates and shell PATH behavior remain unverified;
no OS-changing workflows, networked tests or VMs are run.

## Containers and Kubernetes

| Package | Script | Purpose | Related commands |
|---------|--------|---------|------------------|
| Arch: `docker`, `docker-compose`, `docker-buildx`; Ubuntu: `docker.io`, `docker-compose-v2`, `docker-buildx` | `setup-docker.sh` | Coherent native Engine/Compose/Buildx provider | `d`, `dc`, `dcu`, `dcd`, `dps`, `dex` |
| `minikube` | `setup-minikube.sh` | Local Kubernetes cluster | `minikube` |
| `kubectl` | `setup-minikube.sh` | Kubernetes CLI | `kubectl` |
| `k9s` | `setup-minikube.sh` | Kubernetes TUI | `k9s` |

### Container source and update contract

Implemented for [#148](https://github.com/mikedelafuente/dotfiles-arch/issues/148).
Standalone `setup-docker.sh`, `setup-minikube.sh` and `setup-devcontainer.sh`
support rolling Arch and Ubuntu 26.04 x86_64/amd64. The shared profile runner
keeps Docker/Kubernetes shared and host prerequisites conditional on the additive
`devcontainer` profile; shared bootstrap/sync supports both distros.

| App | Arch source / update owner | Ubuntu source / update owner |
|-----|----------------------------|-------------------------------|
| Engine, Compose, Buildx | Native packages above / guarded pacman | [docker.io](https://packages.ubuntu.com/resolute/docker.io), [docker-compose-v2](https://packages.ubuntu.com/resolute/docker-compose-v2), [docker-buildx](https://packages.ubuntu.com/resolute/docker-buildx) / APT |
| minikube | Native `minikube` / guarded pacman | [Official amd64 binary](https://minikube.sigs.k8s.io/docs/start/) / verified managed release refresh |
| kubectl | Native `kubectl` / guarded pacman | [Official versioned binary and SHA-256](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) / verified managed release refresh |
| k9s | Native `k9s` / guarded pacman | [Official amd64 release](https://github.com/derailed/k9s/releases) / verified managed release refresh |
| lazydocker | Native Extra / guarded pacman | Existing compatible native package or verified release / existing editor update owner |

Ubuntu's official Resolute amd64 main/universe package index was inspected on
2026-10-09: Docker components, just, mkcert and OpenVPN3 are available; minikube,
kubectl and k9s are absent. The Kubernetes tools reuse the existing CLI release
manager (`~/.local/share/dotfiles-arch/editor-tools/<app>`, owned source marker,
versioned directories and `~/.local/bin` links). Native candidates are preferred
if available; compatible existing native installations retain their package update
owner. An existing Ubuntu Kubernetes DEB must have a candidate published by a
configured APT repository; status-only local DEBs fail as an update-owner gap and
remain untouched. CLI baselines are stable minikube/kubectl 1.0+ and k9s 0.1+; **kubectl must
remain within one minor version of your cluster**. The latest upstream release
does not guarantee compatibility with an older remote cluster.

`dfa-update-system` refreshes managed releases after native updates, before writing
success stamps; daily/weekly inherit this. Minikube/k9s use stable official GitHub
metadata with asset SHA-256; kubectl uses `dl.k8s.io` stable metadata and the checksum
for that exact version. Downloads are staged and verified before switching commands;
failures retain the prior release and return nonzero. No installer is piped to a shell.

Fresh Docker setup selects the native family on each distro. Vendor CE/Moby,
Docker Desktop, Podman's Docker shim, unknown/rootless launchers and plugin overrides
are preserved and reported as conflicts; no automatic removal, source switch or
fallback occurs. Podman alone can coexist. Package presence and offline CLI checks
are required for all three components; a Docker executable alone is insufficient.
The script enables `docker.service` and grants the user Docker group membership
(root-equivalent access, effective after logout/login). It does not start test
containers or clusters. Existing plugin directories/config remain untouched.

Verification: `python3 tests/test_container_decisions.py` checks supplied source,
version, capability and temporary-file facts with forbidden-command guards.
`bash scripts/check.sh` checks syntax/ShellCheck; system writes and failure paths
are statically inspected. Engine installation, plugin execution, daemon/group
behavior, release upgrades and Kubernetes cluster/networking behavior are unverified.
No setup/update/service workflows, networked tests or VM provisioning are run.

## Tools and applications (shared)

| Package | Script | Purpose |
|---------|--------|---------|
| Arch `tableplus` (AUR), Ubuntu vendor `tableplus` | `setup-tableplus.sh` | Database GUI |
| Arch `postman-bin` (AUR), Ubuntu official Postman Snap or existing user archive | `setup-postman.sh` | API client |
| Arch `spotify` (AUR), Ubuntu vendor `spotify-client` or existing official Snap | `setup-spotify.sh` | Music |
| Arch native `obsidian` (retain existing `obsidian-bin` AUR), Ubuntu official `obsidian` DEB | `setup-obsidian.sh` | Notes; installer refresh includes Electron |
| Arch `voxtype-bin`/`dotool` (AUR); Ubuntu official `voxtype` DEB + verified dotool source build | `setup-voxtype.sh` | GNOME Wayland dictation — Super+T toggles; uinput typing |
| Arch `cuda`, `cudnn`; Ubuntu scoped NVIDIA CUDA13 runtime libraries | `setup-voxtype.sh` | Parakeet ONNX GPU backend requires AVX-512, working compatible CUDA, driver 580+, runtime ABI and cuDNN9; no driver installs |
| `zed` | `setup-zed.sh` | Code editor |
| `stably-orca-bin` (AUR) | `setup-orca.sh` | [Orca](https://www.onorca.dev/), an IDE for parallel coding agents; launch with `stably-orca` (the `orca` package is the GNOME screen reader) |
| Arch `zsa-keymapp-bin` (AUR), Ubuntu verified pinned Keymapp archive | `setup-moonlander.sh` | ZSA keyboard live layout/firmware flashing; GTK3, WebKitGTK 4.1 and libusb |

### Dictation sources and update owners

Implemented for [#155](https://github.com/mikedelafuente/dotfiles-arch/issues/155).
`bash scripts/setup-voxtype.sh` supports Arch and Ubuntu 26.04 amd64 and retains
GNOME `Super+T` (`/usr/bin/voxtype record toggle`). No X11-only typing replacement.

| Component | Source | Update owner |
| --- | --- | --- |
| Arch Voxtype/dotool | Scanned `voxtype-bin`/`dotool` AUR packages; the selected Voxtype launcher may link to its package-owned backend or use the canonical generated CUDA dispatch wrapper targeting a package-owned binary | Guarded AUR upgrades |
| Ubuntu Voxtype | [Official stable amd64 DEB](https://github.com/peteonrails/voxtype/releases), minimum 1.1.0; stage and verify the release API SHA256 digest before APT installation | `dfa-update-system` checks stable releases; APT alone cannot refresh a standalone DEB. A compatible existing repository package keeps its repository owner. |
| Ubuntu dotool | [Official source](https://git.sr.ht/~geb/dotool), 1.6 commit `180af21c46dcc848d93dbec2644c011f4eea1592`, SHA256 `960f83d4fa33f9d8a8b162663b4185a970a27f37d972d4496457eff6e0b6613c` | Repo-reviewed pin changes rebuilt by standalone setup/`dfa-update-system` into `dotool` 1.6-1dfa1 local DEB. Compatible existing repository packages retain their owner. |
| Ubuntu dotool build dependencies | Native `build-essential`, `golang-go`, `libxkbcommon-dev`, `pkg-config`, `scdoc` | APT; unprivileged staged build, pinned Go dependencies, checksum database enabled and `GOTOOLCHAIN=local` |
| Whisper CPU/Vulkan | Voxtype baseline x86-64-v2, AVX2 or AVX-512 variant; Vulkan additionally needs AVX2, `libvulkan1` and a working hardware Vulkan device | Voxtype owner/native loader; drivers retained. New default model is `base.en`. |
| Parakeet CUDA13 | Voxtype bundled CUDA13 providers/ORT; AVX-512, working CUDA, driver 580+, every visible GPU sm70–sm120 | Voxtype owner plus runtime libraries below. New default is `parakeet-tdt-0.6b-v3`. |
| Ubuntu CUDA13 runtime | [NVIDIA ubuntu2604/x86_64](https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/), repository-scoped fingerprint `14BAFBC7562AD710CA04E69905FBB6DA60DF8A40` | APT. `cuda-cudart-13-4`, `libcublas-13-4`, `libcufft-13-4`, `libcurand-13-4`, `libcudnn9-cuda-13`, and their three toolkit config dependencies only; all other vendor packages pinned negative. No `cuda`/driver metapackages or older Ubuntu repository. |
| Existing Parakeet CPU/CUDA12 | Retain compatible selected variant/config; AVX2/AVX-512 CPU or actual existing CUDA12/cuDNN9/provider runtime | Existing owner. No CUDA12 source substitution; missing/incompatible runtime returns failure. |

Recognized older Voxtype/dotool owners may refresh through their selected source.
Standalone setup refreshes incompatible native/AUR packages without changing owners;
setup and system updates fail if the resulting versions still miss these minimums.
Standalone AUR refresh requires terminal review even with `--yes`.

Unknown launchers, unowned source builds, duplicate sources, older/unscoped NVIDIA
sources, pin conflicts, APT holds and driver/removal plans are retained and reported.
Holds defer installer/build updates; they do not authorize source migration.
Ubuntu's native `nvidia-cudnn` installer is not substituted for cuDNN9/CUDA13.
The release-owner marker `/var/lib/dotfiles-arch/dictation/voxtype-source` and
dotool's package-owned source marker prevent a later repository candidate from
silently taking over a managed local installation.
Direct dotool needs no daemon; its upstream rule uses the `input` group and writable
`/dev/uinput`. This group permits access to **all keyboard devices**. Setup does not
grant access automatically: it fails with instructions when device access is pending.
After choosing that policy, run `sudo usermod -aG input "$USER"`, log out/in, and
check that `uinput` exists and its packaged rule is loaded. Reload the installed
rule explicitly with `sudo udevadm control --reload-rules` and
`sudo udevadm trigger --name-match=uinput` if needed. Custom rules are preserved.

User config/models stay under `USER_HOME_DIR`; run setup as that user. New configs
disable evdev hotkeys and select `output.mode="type"`, `driver_order=["dotool","clipboard"]`.
Existing TOML/models/units/drop-ins are never overwritten or recursively chowned.
An incompatible engine/backend or custom service requires explicit resolution;
the exact legacy upstream-generated user unit is retained as compatible. Absolute
[XDG config/data overrides](https://github.com/peteonrails/voxtype/blob/v1.1.0/src/config/root.rs)
are honored without changing existing ownership; a compatible system config is
also retained instead of being shadowed by a new user file.
GPU selection uses stable `setup variant --to`, with isolated privileged HOME;
CUDA uses the canonical executable wrapper so providers stay discoverable.
Setup downloads a model **only for a new config**, without `--activate`; later
model downloads are separate user actions:
`voxtype setup --download --model base.en --no-post-install`, or
`voxtype setup --download --model parakeet-tdt-0.6b-v3 --no-post-install`.
Changing engines/models is explicit via Voxtype configuration/model commands.
For non-US layouts, match Voxtype's dotool XKB hint and the active GNOME layout.

The package-owned user service is enabled for a new ready config. Existing inactive
services remain inactive; start explicitly with
`systemctl --user enable --now voxtype.service`. Updates restore the chosen backend
after a package refresh and restart only a previously active intended service.
They never fetch models, edit user config or enable a disabled service. Clipboard
fallback, package presence and active service status do not prove direct typing.

Validation is Bash syntax/ShellCheck and static inspection. The supplied-fact check
`tests/test_dictation_decisions.py` is written and deliberately unrun. Release/build
installation, Go compilation, linker/provider loading, model downloads/inference,
microphone capture, uinput access/typing, service behavior and GNOME dispatch are
unverified; no installer, service, driver, model or device workflow was executed.

### Desktop utility sources and update owners

Implemented for [#152](https://github.com/mikedelafuente/dotfiles-arch/issues/152).
The existing shared profile runner selects all five apps on both hosts; standalone
setup paths are enabled on Ubuntu 26.04 amd64. User preferences, Obsidian vaults,
database credentials, Postman collections and login state remain user-owned.

| App / command | Arch source / update owner | Ubuntu source / update owner |
|---------------|----------------------------|-------------------------------|
| TablePlus / `tableplus` | Scanned AUR `tableplus` / guarded yay | [Official Ubuntu 26 APT repository](https://tableplus.com/download/linux) / APT |
| Postman / `postman` | Scanned AUR `postman-bin` / guarded yay | [Verified official Postman Snap](https://snapcraft.io/postman) / Snap automatic refresh; preserve known writable user archives 9.13+ / genuine in-app updater |
| Spotify / `spotify` | Scanned AUR `spotify` / guarded yay | [Official vendor APT](https://www.spotify.com/us/download/linux/) / APT; preserve an existing official Spotify Snap / Snap automatic refresh |
| Obsidian / `obsidian` | [Native Extra](https://archlinux.org/packages/extra/x86_64/obsidian/) / pacman; preserve existing `obsidian-bin` / guarded yay | [Official stable amd64 DEB](https://github.com/obsidianmd/obsidian-releases/releases) with GitHub SHA-256 / common maintenance installer refresh |
| Keymapp / `keymapp` | Scanned AUR `zsa-keymapp-bin` and dependencies / guarded yay | [Official ZSA archive](https://www.zsa.io/keymapp) / reviewed version/checksum pin and common maintenance verification/refresh |

Ubuntu's native catalog does not supply these five apps with the required vendor
workflows. TablePlus uses `https://deb.tableplus.com/debian/26 tableplus main`;
Spotify uses `https://repository.spotify.com stable non-free`. Each APT source uses
`arch=amd64`, a repository-specific `signed-by=/usr/share/keyrings/<app>.gpg`,
one pinned primary signing key, and a candidate-origin check. Existing compatible
scoped sources retain their paths. Duplicate, disabled, wrong-release, globally
trusted or unofficial sources fail without automatic migration. Vendor examples
using `trusted.gpg.d` are deliberately narrowed to repository-scoped trust here.

Primary-key fingerprints inspected on 2026-10-09:

- TablePlus: `211438D2880D8D98E100B1412A17818B38772786`.
- Spotify: `E1096BCBFF6D418796DE78515384CE82BA52C83A` (vendor key URL ends `5384CE82BA52C83A.asc`). Rotation requires reviewed pin changes.

Postman's Snap is the vendor-recommended bundled-library exception; the official
Snap ID is `fFcOtEEF4EdyYb95IUE5Isy28tICYMLf` (publisher `postman-inc`).
Spotify's existing official Snap ID is `pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7`.
Setup checks those asserted identities and retains existing stable channels;
maintenance leaves Snap automatic updates and holds in control rather than using
an explicit refresh that could override a hold. Fresh Postman installs use
`latest/stable`. Recognized writable user Postman archives retain their
[in-app updater](https://learning.postman.com/docs/getting-started/installation/update);
keep updates enabled and restart to apply downloads. Disabled in-app updates
require user action; common maintenance never rewrites app settings or claims to
have applied an in-app update. New archive installation is not selected because
the download lacks independently published integrity metadata; no silent fallback
from failed Snap acquisition occurs.

[Obsidian's automatic updater](https://obsidian.md/help/updates) updates the app,
but cannot update the Electron installer runtime. `dfa-update-system` separately
checks official stable DEB metadata, stages a SHA-256 verified amd64 artifact,
checks package name/version/architecture, and installs only a newer installer.
APT holds defer this refresh without overriding policy. Obsidian can show a newer
app version than its installed package; compare **Settings → General → installer
version** when diagnosing runtime requirements. Existing AppImages/tar archives
with unknown installer ownership are preserved and reported as required source
gaps, not marked current merely because in-app updates work. There is no official
Obsidian APT repository; a standalone DEB does not update through APT alone.

Keymapp's vendor publishes a mutable `keymapp-latest.tar.gz` without a published
signature/checksum. The reviewed 1.3.7 pin
`a87bc7083cd6461ba10e0da4b94f249a29100d712542d54498f01e947cf868fa`
matches the [IoC-inspected AUR packaging source](https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=zsa-keymapp-bin)
and the official downloaded archive. Only regular `keymapp`/`icon.png` members
are extracted; the binary must identify as x86_64 ELF. The user-owned release lives
under `USER_HOME_DIR/.local/share/dotfiles-arch/keymapp/1.3.7`, with a stable
`current` link, executable link and separate `dfa-keymapp.desktop` launcher.
Reviewed pin changes publish a new version and atomically switch `current`,
retaining the previous release. Common maintenance verifies
the vendor archive against the pin before changing a working installation. If
the vendor changes bytes, refresh fails clearly and requires a reviewed
version/checksum update in the recipe; no unverified "latest" replacement occurs.
No genuine installer updater is documented, so the repository pin owns archive
refreshes. Ubuntu dependencies are native `libusb-1.0-0`, `libgtk-3-0t64` and
`libwebkit2gtk-4.1-0` (verified in the official Resolute catalog).

`setup-moonlander.sh` installs the shared [ZSA udev permissions](https://github.com/zsa/wally/wiki/Linux-install)
from `scripts/zsa-udev.rules`, creates/adds the real user to `plugdev`, and reloads
rules only when first installing them. Existing files containing all required
rules retain user additions/comments; different rules or symlinks fail for manual
review. The vendor's device-ID-scoped flashing permissions are retained, including
its `0666` bootloader rules. There is no global `udevadm trigger`: log out/back in
for group changes, then replug the keyboard. Keymapp 1.2+ requires WebKitGTK 4.1.
Wayland launch, sandbox behavior, firmware/live training, group activation and
keyboard access remain unverified; no installer, updater, service or device action
was executed for validation. The offline selection/source regression check is
`tests/test_desktop_utility_decisions.py`, deliberately left unrun; validation was
direct Bash syntax/ShellCheck and source/acquisition/udev inspection only.

## Profile extras

Profiles are **additive multi-select** — enable any combination on one machine
(`SETUP_PROFILES`, e.g. `work devcontainer`). Shared stack always installs first.

### work — `setup-zoom.sh`, `setup-slack.sh`, `setup-chrome.sh`

| Package | Purpose | Related commands |
|---------|---------|-------------------|
| `zoom` (AUR) | Meetings | — |
| `slack-desktop` (AUR) | Team chat | — |
| `google-chrome` (AUR) | Work browser (Super+B when work is selected) | — |
| NinjaOne (Arch: local `ninjaone-agent`; Ubuntu: vendor native DEB) | Opt-in endpoint agent; vendor/IT self-updates, `dfa-weekly` checks health; never enrolled by bootstrap/sync | `dfa-install-ninjaone`, `dfa-update-ninjaone`, `dfa-uninstall-ninjaone` |

### personal — `setup-steam.sh`, `setup-discord.sh`, `setup-firefox.sh`, `setup-mullvad.sh`

| Package | Purpose | Related commands |
|---------|---------|------------------|
| `steam` (Arch multilib) / `steam-installer` + `steam-libs-i386:i386` (Ubuntu multiverse/universe) | Games; native launcher plus Valve client updater | `steam` |
| `discord` (Arch native; Ubuntu official DEB bootstrap) | Chat; Linux app updater retains user settings | `discord` |
| `firefox` (Arch native; Ubuntu signed user archive, or retained Mozilla Snap/APT) | Personal browser (Super+B when personal is selected and work is not) | `firefox` |
| `mullvad-vpn-bin` + its `mullvad-vpn-daemon-bin` CLI dependency (Arch AUR) / `mullvad-vpn` (Ubuntu vendor APT) | VPN; account, connection and other VPNs unchanged | `mvup`, `mvdown`, `mvst` |

### devcontainer — `setup-devcontainer.sh`

Host prerequisites for the platform / work devcontainer sandbox.
Docker and GitHub CLI are already on the shared stack; this profile adds
the rest of the host checklist (tools, DNS, watches, CA trust).

| Package / config | Purpose | Related commands |
|------------------|---------|------------------|
| `just` (both distros, native) | Host lifecycle recipes / pacman or APT updates | `just`, `just --list` |
| `mkcert` (both distros, native) | Local TLS CA / pacman or APT updates | `mkcert -install` |
| Arch `nss` / Ubuntu `libnss3-tools` | `certutil` for Firefox/trust stores / pacman or APT updates | — |
| Arch `bind` / Ubuntu `bind9-dnsutils` | `dig` for DNS checks / pacman or APT updates | `dig @127.0.0.1 -p 5354 …` |
| Arch `openvpn3` (scanned AUR) / Ubuntu `openvpn3-client` (native) | OpenVPN3 CloudConnexa/work VPN / guarded AUR or APT updates | `openvpn3 config-import`, `session-start`, `sessions-list`, `session-manage` |
| `/etc/systemd/resolved.conf.d/dotfiles-arch-test.conf` | Route `Domains=~test` to `127.0.0.1:5354` | restart `systemd-resolved` |
| `/etc/sysctl.d/99-dotfiles-arch-inotify.conf` | Raise `fs.inotify.max_user_watches` to 524288 | — |

Ubuntu sources: [just](https://packages.ubuntu.com/resolute/just),
[mkcert](https://packages.ubuntu.com/resolute/mkcert),
[NSS tools](https://packages.ubuntu.com/resolute/libnss3-tools),
[DNS tools](https://packages.ubuntu.com/resolute/bind9-dnsutils),
[OpenVPN3](https://packages.ubuntu.com/resolute/openvpn3-client).
[OpenVPN upstream lists native Ubuntu 26.04 availability](https://community.openvpn.net/Pages/OpenVPN3Linux).
No additional APT source/key is registered by this slice. Unknown/unowned commands
fail without installing duplicates. Native apps update through `dfa-update-system`;
Arch OpenVPN3 keeps IoC-scanned AUR acquisition and updates.

Run host setup as your workstation user. `mkcert -install` is never invoked with
sudo; its CA/key stay user-owned (mkcert may request sudo for system trust).
Project certificates are generated after clone. The native Ubuntu admin command
is `/usr/sbin/openvpn3-admin`, Arch's is `/usr/bin/openvpn3-admin`. Backend
D-Bus registration files are required; setup runs `init-config --write-configs`
and reloads `dbus.service`. No VPN is imported/started and no DCO/driver package
is installed; missing client/admin/backend or failed configuration is an error.

Split DNS requires an already-active `systemd-resolved.service` and
`/etc/resolv.conf` using `/run/systemd/resolve/stub-resolv.conf`. Hosts with another
resolver policy fail clearly for explicit configuration; setup does not replace
that policy. The managed drop-in routes only `~test` to `127.0.0.1:5354`; setup restarts
resolved on reruns too, so a previously failed apply is retried. Watcher configuration retains limits above
524288 and applies only its own sysctl file. Symlink conflicts are preserved.
VPN, certificate trust, resolver routing and live watcher behavior are unverified.
These gaps or failed writes return nonzero instead of a completed host setup.

## Graphics (optional)

| Package | Script | Purpose |
|---------|--------|---------|
| `nvidia-open-dkms`, `nvidia-utils`, `nvidia-settings`, `linux-headers` | `setup-nvidia.sh` | NVIDIA drivers, installed only when `INSTALL_NVIDIA=true` |

### GPU sources, capability gates and update owners

| Component | Arch source | Ubuntu 26.04 source | Update owner / requirements |
| --- | --- | --- | --- |
| Optional NVIDIA | Native `nvidia-open-dkms`, `nvidia-utils`, `nvidia-settings`, `linux-headers` for a new Turing+ installation | Native `ubuntu-drivers-common` hardware recommendation; signed `linux-modules-nvidia-<branch>-<running-kernel>` preferred, Ubuntu DKMS otherwise | Native pacman/APT; saved explicit `INSTALL_NVIDIA=true` or `bash scripts/setup-nvidia.sh --install`. `--yes`, PCI detection and an unset preference do not opt in. All existing flavors, utility-only stacks, manual and work-managed installations remain untouched; no CUDA repository, purge or module loading |
| CUDA Ollama | Native `ollama-cuda` and its `cuda` dependency | Official stable amd64 archive bundles CUDA runtime libraries; only the existing host driver is used | Ollama 0.40.0+ for the current runtime layout; native owner or verified archive refresh by `dfa-update-system` |
| Vulkan Ollama | Native `ollama-vulkan` and `vulkan-icd-loader`; existing hardware ICD retained | Official archive bundles the Vulkan backend; host Vulkan loader/ICD remain native/vendor-owned | Same owner; Vulkan 1.2+ on a successfully enumerated discrete/integrated GPU. CPU software ICDs do not qualify |
| GPU probes | Native `python`, `vulkan-tools` | Native `python3`, `vulkan-tools` | Native package updates. NVIDIA readiness needs a supported compute capability/driver and successful CUDA initialization/device enumeration with the current user's permissions. Vulkan readiness uses `vulkaninfo --summary`, not executable or ICD presence |
| Archive prerequisites | Native `curl`, `jq`, `ca-certificates`, `zstd`, `python` if a managed archive already exists | Native `curl`, `jq`, `ca-certificates`, `zstd`, `python3` | Native package updates; SHA256 verified before archive extraction or switching a working installation |

[Ollama's Linux instructions](https://docs.ollama.com/linux) offer archives rather
than an official vendor APT repository. A compatible native Ubuntu candidate is
preferred if available; a local DEB without a repository candidate is a source
conflict. The [official stable v0.40.2 release](https://github.com/ollama/ollama/releases/tag/v0.40.2)
was inspected on 2026-10-09: `ollama-linux-amd64.tar.zst` has a GitHub SHA256
digest and the [pinned release build](https://github.com/ollama/ollama/blob/v0.40.2/.github/workflows/release.yaml)
bundles CUDA v12/v13 and Vulkan. Setup resolves current stable metadata each time,
requires a digest and the expected GPU libraries, and does not silently fall back.

Archives reuse the managed release layout at
`~/.local/share/dotfiles-arch/editor-tools/ollama/<version>` with `current` and
`~/.local/bin/ollama`. Ubuntu archive installs use the current user's
`~/.config/systemd/user/ollama.service`, loopback port 11434, Vulkan enabled,
and the default user model store. The service starts with the user session;
setup does not enable lingering, create service accounts, download models or
grant extra device groups/capabilities. Native installs retain their
package-owned system service. Source/launcher/unit/drop-in conflicts are reported
before replacement; arbitrary upstream/manual installs are not adopted.

[Current upstream NVIDIA requirements](https://docs.ollama.com/gpu) are compute
capability 5.0+ and driver 550+, with driver 570+ for compute capabilities
5.0–6.2. Existing CPU-only/ROCm Ollama flavors are preserved and report a pending
GPU capability rather than being replaced. Missing CUDA/Vulkan capability skips
a new installation; a previously installed app with missing capability fails
with a diagnostic. Native service-user GPU access can differ from the interactive
user and still requires runtime verification. Vulkan VRAM measurements can be
approximate without additional capabilities; setup does not grant those capabilities.

`dfa-update-system` refreshes recognized archives and verifies services before a
success stamp. Archive upgrades restart the active user service; updates do not
enable a disabled service. Acquisition, service and local-model-list failures
return nonzero and retain harness configuration. NVIDIA installation/activation,
Secure Boot/MOK enrollment, device permissions, archive compatibility, service
startup, actual GPU inference, model loading and upgrades remain unverified.
New Arch open-driver installs require recognized Turing+ PCI chipset names;
legacy or unknown chipsets defer manual driver selection. Package installation
does not prove GPU readiness; reboot/MOK steps are reported
as pending, following [Ubuntu's driver guidance](https://ubuntu.com/desktop/docs/en/latest/how-to/graphics/install-nvidia-drivers/).

`tests/test_gpu_decisions.py` contains isolated supplied-fact checks with blocked
OS/network/GPU commands. It was left unrun under the implementation constraint;
only Bash syntax, direct ShellCheck and static operation inspection were used.

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

### Shared agent skill: council

`agent-council` is a repository skill, requiring no additional package. Existing
Claude Code, Codex, opencode (when configured for these skills), and Pi harnesses
can engage relevant product/engineering roles with distinct responsibilities,
BA-led domain research, TPM-led integration research, and bounded debate. Research
checks existing findings first and is saved in `docs/market-research/` by default
unless explicitly told not to store it. Distribute
through `dfa-sync-skills` (Claude/Cursor/detected Codex/Pi). `/grill-me` and
`/grill-with-docs` use the coordinator's own recommendations;
`/advise-me` and `/advise-with-docs` automatically
use the council through `advising`. The `with-docs` variants record accepted
terms/decisions in glossary/ADRs. Carry accepted Q/A to `/to-spec`
or `/to-tickets`, and use `/bro` for a plain explanation. Skill invocations are
agent prompts, not shell commands. See [examples](skills/mikedelafuente/agent-council/references/examples.md).
Personal `/ask-mike`, `/council-handoff spec|tickets`, `/build-with-ponytail`, and
`/review-changes` compose unchanged upstream skills without additional packages.
`/setup-dark-factory`, `/dark-factory-idea`, `/dark-factory`,
`/dark-factory-supervisor` and `/dark-factory-retro` add bounded project contracts,
versioned idea approval, independent acceptance and prototype trial pauses.
Their local control seam uses the existing Python standard library; no runner,
tracker plugin or scheduler is installed. Actual adapter configuration, schedules,
actions and synthetic retro publication require accepted project authority.
See [factory contracts](skills/mikedelafuente/dark-factory/references/contracts.md).
`dfa-sync-skills` discovers nested skill folders and gives dotfiles-arch final
priority. `dfa-sync-sources add <path> --overwritable true` allows duplicate
replacement from that source; false is the default and blocks replacement before
links change; see [source groups and updates](skills/README.md).

`dfa-sync-sources` manager option **5** toggles skill overwrites for an existing
source. It displays the current setting; changes apply on the next skill sync.

### Cloud agent config (no additional packages)

`bash scripts/install-cloud-agent-config.sh --home "$HOME"` distributes this
checkout's shared skills and flattened global rule baseline to a cloud user's
agent directories. Requires existing Bash, Python 3.8+, and ordinary shell
utilities; installs no Arch packages, agent CLIs, or desktop configuration.
See [cloud setup](README.md#shared-agent-config-in-cloud-checkouts).


## Desktop IDE sources and update owners (Arch / Ubuntu 26.04)

| Application / commands | Arch | Ubuntu 26.04 | Update owner |
|------------------------|------|--------------|--------------|
| Zed / `zed`, `zeditor`, `dev` | Official Extra `zed`; only this transition removes legacy `~/.local/zed.app` | Verified official stable amd64 archive at `~/.local/zed.app`; retain recognized compatible native/user installs | pacman/APT for native; Zed's in-app self-updater for user installs (disabled updates retain user/IT policy) |
| Stably Orca / `stably-orca`, `orca-ide` | IoC-scanned `stably-orca-bin` AUR | Verified official amd64 AppImage in `~/.local/share/dotfiles-arch/orca/Orca.AppImage`; `libfuse2t64` supplies FUSE2 | Guarded AUR on Arch; AppImage's in-app self-updater on Ubuntu (disabled updates retain user/IT policy) |
| Existing Ubuntu `orca-ide` DEB | — | Preserve the installed package instead of replacing it with an AppImage | Verified official stable DEB refresh through `dfa-update-system`; in-app notifications alone do **not** install updates |

Favor true self-updating user installations on Ubuntu. Existing compatible sources
retain their owners. AppImage replacements keep the fixed pathname so command
links and desktop entries survive. No `orca` alias is created: that name belongs
to GNOME's screen reader. No installer script, PPA, foreign APT suite, source
fallback, sandbox bypass, or driver replacement is added. Shared orchestration and standalone setup use these same source decisions.

Evidence checked 2026-10-08: [Zed Linux installation](https://zed.dev/docs/linux),
[Zed self-updates](https://zed.dev/docs/update), and
[Orca installation/update distinctions](https://www.onorca.dev/docs/install).
Official stable release metadata supplied Zed **1.23.2** and Orca **1.4.223**
with SHA-256 digests for `zed-linux-x86_64.tar.gz`, `orca-linux.AppImage`, and
`orca-ide_1.4.223_amd64.deb`. Setup resolves current stable metadata, exact asset
names and official URLs; missing digests, unsupported assets, prereleases and
unknown ownership fail explicitly. SHA-256 verifies integrity against official
HTTPS metadata, not an independent publisher signature. DEB refresh validates
package name, architecture and version, preserves package holds, refuses removals,
never downgrades, and returns failures before update success stamps.

Zed requires **1.18+** for the shared terminal-thread settings, system glibc
**2.31+** and Vulkan support. A missing Vulkan ICD is reported; even a present ICD
is not proof of a working GPU. Native and user command aliases must resolve to
one installation; unknown or shadowing commands fail. User trees without a
selected launcher are preserved and reported rather than adopted. Zed config
uses the existing conflict-safe per-file linker, preserving extra user files and
the default-harness/terminal-thread configuration. Existing unrelated desktop
entries and MIME defaults are preserved; new entries declare no directory MIME.
Only missing or already-Zed text/source defaults are eligible. An old Zed
`inode/directory` association can still be returned to installed Nautilus.

Validation: supplied source/version/release facts and temporary command links in
`tests/test_editor_decisions.py`, plus Bash syntax, ShellCheck and static review.
Installation, archive/AppImage execution, DEB upgrades, self-update replacement,
FUSE/sandbox behavior, shared settings compatibility, desktop/MIME integration and
Vulkan/Wayland runtime are **unverified**. No setup/update/cleanup/service/driver/
GNOME workflow or networked test was executed. Resolve reported source conflicts
explicitly; do not silently migrate a managed/work installation.

### Agent harnesses and ChatGPT distro slice

Implemented for [#146](https://github.com/mikedelafuente/dotfiles-arch/issues/146).

| App | Arch source | Ubuntu 26.04 amd64 source | Update owner |
| --- | --- | --- | --- |
| Claude Code | User npm `@anthropic-ai/claude-code`; retain recognized user-native installs | New: signed stable native binary; retain existing npm/native or scoped official APT | Native: background + `claude update`; npm: `dfa-update-npm-clis`; retained APT: `dfa-update-system` |
| Codex CLI | User npm `@openai/codex` | Same | `dfa-update-npm-clis` |
| Pi | User npm `@earendil-works/pi-coding-agent`, lifecycle scripts blocked | Same | `dfa-update-npm-clis`, also with `--ignore-scripts` |
| opencode CLI | Official `opencode` package; retain existing user npm if recognized | Stable user npm `opencode-ai`, documented source exception | Native: `dfa-update-system`; npm: `dfa-update-npm-clis` |
| Selected official ChatGPT desktop | Guarded `chatgpt-desktop` AUR recipe; retain existing official `chatgpt` package | Official `chatgpt` from scoped, signed OpenAI APT repository | `dfa-update-system` (Arch AUR/native or Ubuntu APT) |

[Stable opencode instructions](https://opencode.ai/docs/) document `opencode-ai`
and Arch's native package. This slice retains the `opencode` CLI identity and
existing provider configuration; it does not switch to the beta `opencode2` CLI.
Claude/Codex/Pi retain existing npm sources. New Ubuntu Claude uses the signed
native installer; `DISABLE_UPDATES` defers recurring native/npm refresh without
rewriting policy. `DISABLE_AUTOUPDATER` permits the explicitly invoked native updater. Setup/update refuse root invocation
and system npm prefixes, verify resolved launcher ownership, and preserve unknown
installations with a source-conflict failure. Existing npm script allowlists are
extended only when installing missing Claude/opencode. CLI sources must be
resolved explicitly when a native package shadows npm or another installation.
Recognized native Claude remains usable without NVM/npm. Missing npm for an
installed unrecognized launcher is a failure, not a successful maintenance skip.

[Official ChatGPT Linux instructions](https://learn.chatgpt.com/docs/linux/linux-app)
confirm Ubuntu 26.04 and signed package-manager updates. The existing
[AUR recipe](https://aur.archlinux.org/packages/chatgpt-desktop) repackages that same
OpenAI binary; no alternative ChatGPT wrapper is substituted. Read-only source
inspection on 2026-10-08 found vendor amd64 package `26.1007.21434` and inspected
only its DEB control archive via an HTTP byte range, without executing it.
The vendor postinst uses `/etc/apt/sources.list.d/chatgpt.sources` and
`/usr/share/keyrings/chatgpt-archive-keyring.gpg`; this slice prepares that exact
scoped source before APT acquisition, avoiding an unverified standalone DEB.
`scripts/keys/chatgpt.asc` is the public signing key extracted from that vendor
postinst, fingerprint `3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`.
The source is `https://persistent.oaistatic.com/codex-app-prod/linux/deb`, suite
`stable`, component `main`, architecture `amd64`. APT verifies metadata/artifact
integrity with this key; no global trust or pipe-to-shell installer is added.
Unknown launchers, duplicate source declarations, altered source/key files, and
an existing repository opt-out are retained and reported as conflicts. Key
rotation needs a reviewed fingerprint/key update. Ubuntu automatic security
updates, holds, pins, and management policies remain with existing owners.

No command names, bootstrap preferences, profile selection, schema versions, or
shared harness detection/fallback change. Codex setup enables only
`[features].hooks`, removes its deprecated `codex_hooks` entry, and preserves
unrelated TOML data/comments; malformed or unsafe inline/dotted feature tables
fail with preservation diagnostics. JSON reveal hooks merge into existing
`PostToolUse`, preserving other hooks/preferences. Missing jq or malformed hook
JSON fails setup. Local Ollama model integration remains optional: absent or
unavailable service skips; a failed required config refresh returns nonzero to
`dfa-daily`. Model names are validated before writing TOML. Codex uses its built-in
Ollama provider; opencode retains the shared OpenAI-compatible provider shape.
Real commented JSONC remains unsupported and is reported as a model-sync failure.

Inspect without running setup/update:

```bash
jq '.hooks.PostToolUse' ~/.claude/settings.json ~/.codex/hooks.json
sed -n '/^\[features\]/,/^\[/p' ~/.codex/config.toml
cat /etc/apt/sources.list.d/chatgpt.sources  # Ubuntu
python3 tests/test_harness_decisions.py
bash scripts/check.sh
```

Owner selection/source conflicts and Codex TOML transformations are checked with
supplied host/package/source facts, strings, and temporary files, with forbidden
command guards. No test invokes setup, updater, package/service/desktop commands,
or a network endpoint. Bash syntax/ShellCheck cover all shell entrypoints; there
is no typechecker for these shell/Python scripts. Static inspection confirms
CLI/hook/ChatGPT/model-refresh failures propagate through existing setup/daily
aggregators; npm CLI refreshes do not write system-update stamps. Shared default
harness detection, launchers, and Ollama dispatch were inspected without execution.

Installation, npm/native/AUR/APT updates, vendor maintainer-script behavior, app
launch/login, hooks inside live agents, default-harness runtime fallback, and
Ollama model use on either workstation remain **unverified**. Wayland behavior
is also unverified; upstream calls native Wayland experimental. Shared Ubuntu
orchestration and optional GPU-gated Ollama acquisition use the same owners.


## Work app sources and update owners

Standalone `setup-chrome.sh`, `setup-slack.sh`, and `setup-zoom.sh` support rolling
Arch and Ubuntu 26.04 amd64. The single profile runner still selects all three
only when `work` is selected (also alongside `personal`/`devcontainer`). Full
Shared Ubuntu bootstrap/sync/profile/GNOME setup uses the same recipes.

| App / launcher / desktop | Arch source | Ubuntu source | Update owner |
|---|---|---|---|
| Chrome / `google-chrome-stable`, `google-chrome` / `google-chrome.desktop` | IoC-scanned `google-chrome` AUR | Google's stable APT (`google-chrome-stable`); `dl.google.com/linux/chrome-stable/deb`, stable/main | Guarded AUR or APT through `dfa-update-system`, daily/weekly |
| Slack / `slack` / `slack.desktop` | IoC-scanned `slack-desktop` AUR | Slack's Packagecloud APT (`slack-desktop`); `packagecloud.io/slacktechnologies/slack/debian`, jessie/main | Guarded AUR or APT through common maintenance; candidate and installed package require 4.35.121+ source handling |
| Zoom / `zoom` / `Zoom.desktop` | IoC-scanned `zoom` AUR | Official signed `zoom_amd64.deb` from `zoom.us/client/latest` | Explicit verified-DEB refresh after APT in `dfa-update-system`; no vendor APT or Linux in-app updater assumed |
| Verification prerequisites | Existing shared tools | `curl`, `ca-certificates`, `gnupg`, `binutils` (`ar`), `python3` | Native package updater |

The vendor app repositories are selected instead of Ubuntu packages because these
three proprietary desktop applications are not native Ubuntu packages. Slack's
`jessie` suite names the vendor's app feed; no Debian OS repository is added.
Chrome/Slack downloads use APT's authenticated metadata and package hashes.
Source registration is idempotent, uses a repository-scoped `Signed-By`, and
preserves existing compatible scoped sources. New registrations use vendor
filenames (`google-chrome.sources`, `slack.list`) and keys in
`/usr/share/keyrings/{google-chrome,slack}.gpg` to avoid a second managed feed.
Candidate policy must name the selected vendor, excluding local-only packages or
third-party candidates. Disabled, malformed, global-trust-only, duplicate, or
unknown feeds fail without silent source migration; repair them explicitly.
Source destinations and key symlinks are not overwritten. Key rotations need a
reviewed fingerprint update, never a signature-policy bypass.

Pinned primary fingerprints (vendor metadata inspected 2026-10-09):

- Google: `EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796`.
- Slack APT metadata: `DB085A08CA13B8ACB917E0F6D938EC0D038651BD` (distinct from Slack's standalone DEB signing key).
- Zoom 6.7.5+ signing key: `84C365D6CC9A4886CA926BCC4F2197399706AC24`.

Zoom's DEB is staged in a temporary directory. GPG authenticates its embedded
`_gpgbuilder` dpkg-sig v4 manifest using an isolated, pinned Zoom keyring; a
read-only Python check verifies every Debian archive member against the signed
size/MD5/SHA1 list before APT installs it. These legacy member digests are Zoom's
signature format, not a newly invented SHA-256 guarantee. Unexpected members,
signature changes, missing signatures, wrong package/architecture, or malformed
versions fail while retaining the working app. The Debian package version prevents
downgrades/reinstalling equal releases. `apt-mark` holds are policy-deferred and
retained; dependency removals are refused. No `dpkg-sig` package availability is
assumed on Ubuntu 26.04, and no remote installer is executed.

Package-owned launchers are required; Snap/Flatpak duplicates and unknown/manual
launchers report conflicts. Existing compatible selected packages retain their
update owner; existing Zoom packages join the explicit signed refresh owner.
Setup never rewrites `~/.config/google-chrome`, `~/.config/Slack`, Zoom settings,
accounts, desktop identities, or browser preferences. The shared GNOME work
preference still targets `google-chrome.desktop`; this slice does not run GNOME
configuration on Ubuntu. Resolve source conflicts before rerunning setup.
Maintenance validates installed work-app ownership/keys before APT, verifies vendor
candidates after metadata refresh, and checks ownership again after native updates.
A failed standalone refresh or source check returns failure and prevents a success
stamp; already completed native updates cannot be rolled back by this check.

Evidence: [Google signing key](https://www.google.com/linuxrepositories/),
[Chrome source registration](https://chromium.googlesource.com/chromium/src/+/lkgr/chrome/installer/linux/common/apt.include),
[Slack Linux install/update guidance](https://slack.com/help/articles/212924728-Download-Slack-for-Linux--beta-.),
[Slack vendor repository and scoped APT key](https://packagecloud.io/app/slacktechnologies/slack/gpg),
[Zoom Linux installation](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063458),
[Zoom signing-key rotation and DEB signatures](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063726),
[Debian dpkg-sig format](https://manpages.debian.org/buster/dpkg-sig/dpkg-sig.1.en.html).

Verified: supplied profile/source/package/candidate decisions, scoped-source and
signed-manifest checks in temporary state (`python3 tests/test_work_app_decisions.py`),
Bash syntax and ShellCheck, and static update-failure/stamp inspection.
Unverified: Ubuntu 26.04 dependency resolution, APT's current cryptographic policy
acceptance of vendor keys, vendor maintainer scripts preserving scoped feeds,
real package installation/upgrade/holds, Zoom's current signature payload,
GNOME launch/default-browser integration, Slack keyring/login/tray integration,
Wayland screen sharing/audio/video, and managed-workstation policies. No package
manager, networked test, live app, service, or desktop workflow was executed as
verification. Vendor Linux support is feasibility evidence, not runtime parity.

### NinjaOne standalone lifecycle — Arch / Ubuntu 26.04

Implemented for [#156](https://github.com/mikedelafuente/dotfiles-arch/issues/156).
`dfa-install-ninjaone` remains standalone and work-profile gated (`--force` overrides
that profile check). Bootstrap/profile setup never enrolls security agents.

| Host / app | Source | Update owner and conflicts |
|------------|--------|----------------------------|
| Arch NinjaOne | Console-issued vendor enrollment DEB, repackaged locally as `ninjaone-agent` | Vendor `ninjarmm-patcher.timer`; weekly health/repair retains the existing Arch runtime dependencies. Arch remains vendor-unsupported. |
| Ubuntu NinjaOne | Console-issued native amd64 DEB installed with APT, retaining vendor maintainer scripts | Vendor agent/patcher, without adding an APT repository. `dfa-update-ninjaone --url <newer URL>` only upgrades our recorded package and enrollment. Existing IT installations are retained. |
| Ubuntu SentinelOne | Existing vendor/IT native `sentinelagent`; never installed directly by these commands | SentinelOne console/vendor owns updates and uninstall authorization. Presence alone does not prove NinjaOne enrollment; removal requires a separate explicit request. |

Download trust: generated `https://*.ninjarmm.com` or `*.rmmservice.com` enrollment
URLs only, without redirects; safe archive paths and regular-file/directory types,
matching URL/DEB version, native agent package identity, and amd64 architecture.
Changed layouts/links/identity fail closed. No generic token installer or source
fallback is added. The enrollment DEB is private temporary data; installer output
is withheld because vendor scripts can print enrollment secrets. No vendor digest
is supplied by these tenant-specific URLs: trust is pinned HTTPS plus archive and
identity checks, not independent signature verification.

Credentials stay in `~/.config/dotfiles-arch/ninjaone.env`, atomically saved as a
user-owned mode-600 regular file. Use the hidden prompt instead of `--url` to avoid
shell history. Ubuntu installs record the exact native package plus a one-way
enrollment digest in root-owned `/var/lib/dotfiles-arch/ninjaone-package` (644);
a saved URL alone never adopts an existing IT-managed agent. Another enrollment,
unknown package ownership, or redirected ownership state is preserved and reported.
The existing bootstrap preferences and schema version do not change.

`dfa-weekly` now calls native health handling on both hosts. Agent and patcher
activity/enabled state are checked. Our recorded installs retain missing-binary
reinstall and service repair; IT-managed/unrecognized installations get read-only
checks and return failure when unhealthy, with no dependency installs, repair,
replacement or URL-driven upgrades. No agent uses the general app-source updater.

`dfa-uninstall-ninjaone [--keep-url]` requires a terminal and typing `remove`;
`--yes` alone cannot authorize removal. On Ubuntu it runs our package's vendor
`ninja-deb-uninstall.sh`, checks for remnants, and retains SentinelOne by default.
`--remove-sentinelone` additionally requires typing `remove SentinelOne` and a
hidden console-issued uninstall passphrase; it invokes the package-owned vendor
`sentinelctl control uninstall` without forced cleanup. The passphrase is neither
saved nor printed and is passed through stdin to avoid sudo command logging;
SentinelOne's documented CLI itself receives it as an argument. Anti-tamper or
uninstall failures remain failures for IT/vendor assistance. Successfully removed
NinjaOne ownership state is cleared immediately, even if SentinelOne later fails,
so weekly health cannot silently reinstall an intentionally removed agent.
Ubuntu never applies Arch's forced dpkg cleanup, account/file deletion, or database
record removal. Arch's existing repackaged-agent/SentinelOne workaround stays
confined to Arch, subject to the same explicit removal confirmation. Unknown
NinjaOne installations must be removed through their IT/vendor owner.

Primary sources: [NinjaOne Linux installation](https://www.ninjaone.com/docs/new-to-ninjaone/agent-installation/linux-device-agent-installation/),
[NinjaOne native removal](https://www.ninjaone.com/es/docs/administracion/agente-ninjaone-guia-de-eliminacion-de-agentes/),
[SentinelOne's vendor uninstall command](https://github.com/Sentinel-One/ansible_collection_s1agents/blob/main/roles/s1_agent_uninstall/tasks/linux.yml),
and [NinjaOne SentinelOne prerequisites](https://www.ninjaone.com/docs/integrations/vulnerability-management/uninstalling-sentinelone-agent/).
These document the Linux/native lifecycle, not certification of Ubuntu 26.04.

Validation: direct Bash syntax and ShellCheck only; archive/native dispatch and
managed-agent boundaries statically inspected. `tests/test_ninjaone_decisions.py`
provides pure supplied URL/version/enrollment/ownership/path checks with forbidden
command guards and temporary state; it is deliberately **unrun**, along with the
updated maintenance check. No installer, uninstaller, service/system mutation,
networked test, test script or VM was executed. Vendor DEB layout/identity,
Ubuntu 26.04 compatibility, enrollment, self-update, native uninstaller behavior
and SentinelOne passphrase/anti-tamper behavior remain **unverified** on hardware.

### Personal apps on Ubuntu 26.04 (amd64)

The additive `personal` profile selects all four existing setup scripts. Individual
`scripts/setup-{steam,discord,firefox,mullvad}.sh` entrypoints support both distros.
No package setup connects a VPN, starts a game, logs in, changes a browser profile,
or replaces unrelated VPN/browser installations. No new command or config key is added.

| App / normalized desktop | Ubuntu selected source | Update owner |
|---|---|---|
| Steam / `steam.desktop` | Native `steam-installer` (multiverse) and `steam-libs-i386:i386` (universe); amd64 host plus i386 foreign architecture | APT owns installer/dependencies via common maintenance; Valve owns client/game updates in user state |
| Discord / `discord.desktop` | Official stable 1.0.161 DEB bootstrap, pinned SHA-256; compatible existing stable DEBs require package-owned executable and Rust updater bootstrap | Genuine Discord Linux updater installs/updates the app in the user's configuration directory on launch; APT owns bootstrap dependencies, no periodic DEB reinstall |
| Firefox / `firefox_firefox.desktop` (Snap) or `firefox.desktop` (DEB/user) | New absent app: signed Mozilla stable user archive plus exact-path AppArmor sandbox attachment; retain stock Snap, Snap bootstrap or existing scoped Mozilla APT | User: genuine in-app updater; retained Snap automatic refresh or Mozilla APT; no source migration or new APT pin |
| Mullvad VPN / `mullvad-vpn.desktop` | Vendor stable APT `repository.mullvad.net/deb/stable`, stable/main; `mullvad-vpn` | APT via `dfa-update-system`, daily/weekly; no direct service/VPN commands in setup |
| Source prerequisites | `software-properties-common` for Steam components, `curl`, `ca-certificates`, `gnupg` for pinned/scoped sources | Native package updates |

Steam setup adds i386 if missing and enables Ubuntu multiverse idempotently with
`add-apt-repository`; universe and native amd64/i386 indexes must be available.
Candidate metadata is cross-checked against Ubuntu `resolute` release indexes,
including official update/security/backport pockets and local Ubuntu mirrors.
Unexpected pinned candidates or source architecture restrictions fail with a
source diagnostic; source architecture restrictions, GPU drivers and package
holds are not rewritten. `steam-launcher`/Valve APT, Steam Snap/Flatpak, manual
launchers, and old standalone `steam:i386` without the native installer report
conflicts; they are never removed or migrated. Existing Steam libraries/client
state are not touched. A missing `/usr/games` PATH entry gains only an owned
`~/.local/bin/steam` symlink, with user-file conflicts rejected. Arch retains
multilib and native Steam; enabling multilib refreshes through the full guarded
upgrade, avoiding a partial Arch upgrade.

Discord published its full Linux Rust updater on 2026-05-04. Read-only inspection
of the official stable DEB confirms `/usr/bin/discord` launches a writable app
in `$XDG_CONFIG_HOME/discord` (otherwise `~/.config/discord`), bootstrapping it
from `updates.discord.com` with `/usr/share/discord/updater_bootstrap` when needed.
The reviewed bootstrap URL is
`https://stable.dl2.discordapp.net/apps/linux/1.0.161/discord-1.0.161.deb`, SHA-256
`1a486a0cd0dc0e79b952b14dd5e361a8614dc28d1d371cd00ebf37a2ad0ce63d`.
This local pin was calculated from official HTTPS bytes; it is not a vendor
signature or independently published checksum. Setup verifies it and DEB
package/version/architecture before installing. Missing or changed pinned bytes
fail without falling back to an unverified download. An alternate Discord APT candidate fails before native upgrade. Existing stable updater
DEBs are preserved; pre-updater DEBs and manual archives report a conflict,
requiring an explicit source repair. Arch uses native `discord`, correcting the
old AUR description. A sole existing stable Snapcrafters Discord Snap retains
its asserted Snap owner instead of changing source; it is a community exception,
not endorsed vendor packaging. Snap confinement/voice/screen sharing remain
unverified. No updater setting, account, or `SKIP_HOST_UPDATE` policy is changed.

Mozilla Snap ID: `3wdHCAVyZEmYsCMFDE9qt92UV8rC8Wdk` (Mozilla publisher).
Retained Discord Snap ID: `qHVefGEBezeuCeSfTND40uoUD6GRw8BO` (Snapcrafters).
Both require `latest/stable`, asserted identity and owned command/desktop exports;
other channels/Flatpaks/unknown publishers are preserved and reported as conflicts.
Ubuntu's Firefox `*snap*` DEB is recognized as the Snap bootstrap, not a duplicate
browser. An existing Mozilla APT feed without its selected DEB is a conflict,
not permission to install a second browser source. Retained Mozilla DEBs need a scoped
`Signed-By`, stable vendor candidate and pinned primary fingerprint
`35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`; no preferences/pins are written.
GNOME consumes the selected desktop ID and retains Chrome's work-over-personal
preference. User desktop overrides are preserved and cause a launcher conflict.

Mullvad's scoped key primary fingerprint is
`A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF` (official key inspected 2026-10-09).
New source/key destinations are `/etc/apt/sources.list.d/mullvad.list` and
`/usr/share/keyrings/mullvad-keyring.gpg`; existing compatible scoped sources/keys
are retained. Disabled/beta/duplicate/malformed/unscoped feeds, unrelated source
owners, or changed keys fail without replacement. APT candidate/owner checks run
before upgrades; failures propagate and cannot advance the system-update stamp.
APT/Snap holds and automatic security updates remain in force. App-owned updates
happen when launched; common maintenance verifies ownership without claiming an
in-app update completed or launching an application.

Evidence checked 2026-10-09: [Ubuntu Steam installer](https://packages.ubuntu.com/resolute/steam-installer),
[32-bit Steam dependency package](https://packages.ubuntu.com/resolute/steam-libs-i386),
[Discord Linux updater announcement](https://discord.com/blog/discord-patch-notes-may-4-2026),
[official Discord download](https://discord.com/download),
[Mozilla's Linux source guidance](https://support.mozilla.org/en-US/kb/install-firefox-linux),
[Mozilla Snap](https://snapcraft.io/firefox), [Snapcrafters Discord exception](https://snapcraft.io/discord),
[Mullvad Linux repository support](https://mullvad.net/en/help/install-mullvad-app-linux).

Validation: direct Bash syntax/ShellCheck plus static inspection only. The pure
supplied-fact checks in `tests/test_personal_app_decisions.py` are left unrun per
user instruction. No setup/update script, test, app, package manager, VPN, GNOME
setting, service, VM, or networked validation workflow was executed. Vendor/source
metadata and archive contents were read without execution as feasibility research.
Unverified: Ubuntu dependency resolution (including Discord's legacy dependency
names), native installation/upgrades and maintainer-script effects, APT signing
policy, Snap refresh/holds and desktop exports, Discord bootstrap/client updates,
Steam client/Proton/games/32-bit GPU libraries, Firefox profiles/default-browser
runtime, and Mullvad daemon/account/VPN/DNS/kill-switch behavior.

## Final Ubuntu source / update audit

Audited 2026-10-09 for [#162](https://github.com/mikedelafuente/dotfiles-arch/issues/162),
against every selected setup in the single profile runner and opt-in NinjaOne.
The detailed per-family source tables above remain the package-purpose catalog.
[Evidence and disabled-update handling](docs/ubuntu-source-update-audit.md) explain
why an update banner, installer rerun, package transaction, content download or
Obsidian app-code update does not prove a complete application self-updater.

New Ubuntu installs prefer verified genuine self-updaters when they meet the
shared configuration/security requirements. Compatible existing sources retain
their owners. Unknown/duplicate sources fail rather than migrate. Every APT row
below means `dfa-update-system` using configured authenticated sources, respecting
holds/pins and automatic security updates; it does **not** mean in-app self-update.
`Refresh` means the existing verified release owner through `dfa-update-system`.
`Pin` means maintainer-reviewed versions/hashes applied by setup/full sync, not
an unattended fetch of unreviewed upstream changes. `Manual` owners are intentionally
not invoked by daily/weekly; those commands never report them refreshed.

Exceptions: **N** = native host/CLI integration, no verified compatible complete
self-updating alternative established; **V** = vendor Linux package-manager source,
no verified complete Linux in-app alternative established; **R** = verified release
refresh because no safe complete self-updater established; **P** = reviewed data/build
pin, no application binary updater; **K** = compatible existing owner retained;
**M** = IT/vendor-managed lifecycle. These are bounded source decisions, not claims
that an upstream project can never add a safe updater.

| Selected app / CLI | Ubuntu source | Update owner / genuine mechanism | Minimum or required capability / exception |
|---|---|---|---|
| Git / `git` | Native `git` | APT; no self-update selected | 2.35+ / N |
| Git Delta / `delta` | Native `git-delta` | APT; no self-update selected | 0.16+ / N |
| curl | Native `curl` | APT; no self-update selected | HTTPS/TLS downloads / N |
| wget | Native `wget` | APT; no self-update selected | Shared CLI / N |
| X clipboard / `xsel` | Native `xsel` | APT; no self-update selected | X compatibility / N |
| Wayland clipboard / `wl-copy`, `wl-paste` | Native `wl-clipboard` | APT; no self-update selected | Wayland / N |
| eza | Native `eza` | APT; no self-update selected | 0.18+ / N |
| Starship | Native `starship` | APT; no self-update selected | 1.22+ / N |
| fzf | Native `fzf` | APT; no self-update selected | 0.48+ / N |
| ripgrep / `rg` | Native `ripgrep` | APT; no self-update selected | 13+ / N |
| fd / `fdfind` | Native `fd-find`, owned executable `fd` link | APT; no self-update selected | 8+; subprocess alias / N |
| bat / `batcat` | Native `bat`, owned executable `bat` link | APT; no self-update selected | 0.23+; shared config / N |
| Glow | Scoped official Charm APT `glow` | APT; no self-update selected | 1+ / V |
| htop | Native `htop` | APT; no self-update selected | Shared CLI / N |
| ncdu | Native `ncdu` | APT; no self-update selected | Shared CLI / N |
| tree | Native `tree` | APT; no self-update selected | Shared CLI / N |
| jq | Native `jq` | APT; no self-update selected | JSON/reveal hooks / N |
| netstat | Native `net-tools` | APT; no self-update selected | Network inspection / N |
| iw | Native `iw` | APT; no self-update selected | Wireless inspection / N |
| btop | Native `btop` | APT; no self-update selected | Shared CLI / N |
| duf | Native `duf` | APT; no self-update selected | Shared CLI / N |
| stow | Native `stow` | APT; no self-update selected | Shared CLI / N |
| ShellCheck | Native `shellcheck` | APT; no self-update selected | Static Bash checking / N |
| GitHub CLI / `gh` | Native `gh` | APT; no self-update selected | 2+ / N |
| tldr | Native `tealdeer` | APT binary; `tldr --update` updates content only | Shared CLI / N |
| fastfetch | Native `fastfetch` | APT; no self-update selected | Shared CLI / N |
| zoxide | Native `zoxide` | APT; no self-update selected | Shared CLI / N |
| Bash/completions | Native `bash`, `bash-completion` | APT; no self-update selected | Bash 4+ / N |
| less / col / SSH | Native `less`, `bsdextrautils`, `openssh-client` | APT; no self-update selected | Shared pager/SSH / N |
| TLS/archive/build helpers | Native `ca-certificates`, `gnupg`, `coreutils`, `tar`, `gzip`, `unzip`, `xz-utils`, `zstd`, `build-essential`, native development headers listed above | APT; no self-update selected | Integrity, extraction, native builds / N |
| Kitty | Native `kitty` | APT; upstream binary install rerun is not a self-updater | Shared Kitty config / N |
| tmux | Native `tmux` | APT; no self-update selected | 3.2+ / N |
| lazygit | Native Universe `lazygit` | APT; no self-update selected | 0.40+ / N |
| lazydocker | Compatible native candidate, otherwise official verified release | APT or Refresh; no self-update selected | 0.20+ / N, R |
| Neovim | Compatible native candidate, otherwise official verified stable archive | APT or Refresh; plugin updates do not update Neovim | 0.12+ / N, R |
| tree-sitter CLI | Compatible native candidate, otherwise official verified release | APT or Refresh; `:TSUpdate` updates parsers only | 0.26.1+ / N, R |
| Zed | Verified stable user archive; native install retained | Genuine in-app binary updater; retained native APT | 1.18+ / K |
| Stably Orca | Verified official AppImage; existing compatible DEB retained | AppImage genuinely self-updates; DEB Refresh (banner alone does not install) | AppImage/FUSE2 and normalized launchers / K |
| Claude Code | Signed stable native binary for missing installs | Genuine startup/background and `claude update`; existing npm uses npm maintenance, scoped APT uses APT | New signed source 2.1.207+; native launcher/layout / K |
| Codex CLI | User npm `@openai/codex` | npm maintenance; installer/update command is not an independent verified in-app owner | User NVM/npm, shared hooks / R |
| Pi | User npm `@earendil-works/pi-coding-agent` | npm maintenance with `--ignore-scripts`; no self-updater selected | User NVM/npm / R |
| OpenCode | User npm `opencode-ai` | npm maintenance; curl-method upgrade pipes downloaded installer to shell and is rejected | Stable CLI/provider config / R |
| Official ChatGPT desktop | Scoped signed OpenAI `chatgpt` APT | APT; no complete Linux in-app updater established | Official amd64 desktop, source/key validation / V |
| NVM / Node / npm | Existing checksum-verified NVM bootstrap and official Node binaries | Manual reviewed NVM bootstrap refresh / `nvm install --lts`; npm does not self-update Node | Node 22+, fresh current LTS / R, K |
| Python / pip / venv / pynvim | Native `python3`, `python3-pip`, `python3-venv`, `python3-pynvim`, `python3-dev` | APT; project venv dependencies remain project-owned | Import/provider checks; no system pip override / N |
| Go / gopls | Native `golang-go`, `gopls` | APT; optional Go toolchain downloading is separate | Compiler/std library; existing toolchain policy / N |
| rustup manager | Official checksum-verified user `rustup-init` for missing installs; existing native/user managers retained | Genuine `rustup self update` for user binary; native APT | Owned identical Rust proxies; no rc-file edits / K |
| Rust / Cargo | Rustup user toolchains or existing native toolchain | Manual `rustup update` updates toolchains; native APT | Stable only when no selected default; pins/nightly retained / K |
| PHP / extensions | Native CLI/extensions/development packages listed above | APT; no self-update selected | Laravel builtins/extensions; CLI SAPI only / N |
| Composer | Verified official installer + user stable PHAR for missing installs; native Composer retained | Genuine manual `composer self-update`; native APT | Native PHP; user PHAR/update keys/settings / K |
| Laravel installer | User Composer global `laravel/installer` | Manual `composer global update laravel/installer`; dependency update, not self-update | Existing Composer home/bin dir retained / R |
| Ruby | Native `ruby`, `ruby-dev` and native build dependencies | APT; no self-update selected | RubyGems/OpenSSL/Psych / N |
| Bundler / Rails | User gems, or existing compatible native commands | Manual `gem update --user-install bundler/rails --no-document`; native APT | Actual user gem dir; no root/system gem update / R, K |
| Docker Engine / Compose / Buildx | Native `docker.io`, `docker-compose-v2`, `docker-buildx` | APT; no self-update selected | Coherent family; CE/Moby/conflicting owners preserved / N |
| minikube | Compatible native or verified official binary | APT or Refresh; update notice is not replacement | 1+ / N, R |
| kubectl | Compatible native or versioned official binary/SHA256 | APT or Refresh; no self-update selected | 1+ / N, R |
| k9s | Compatible native or verified official release | APT or Refresh; no self-update selected | 0.1+ / N, R |
| TablePlus | Scoped official Ubuntu 26 APT | APT; no verified complete Linux self-updating source established | Vendor native database GUI / V |
| Postman | Official verified stable Snap; known writable user archive retained | Snap refresh is store-owned; retained archive genuinely updates in-app | User archive 9.13+; new archive lacks published initial integrity metadata / R, K |
| Spotify | Scoped official vendor APT; existing official Snap retained | APT or Snap store; generic desktop update instructions do not establish a safe Linux user source | Native/vendor desktop / V, K |
| Obsidian | Official verified stable amd64 DEB | Genuine in-app ASAR updates **plus** Refresh for installer/Electron | Installer updates remain necessary; no full runtime self-updater established / R |
| Keymapp | Reviewed verified official user archive | Pin + common maintenance verification/refresh; no complete verified self-updater established | 1.2+; GTK3, WebKitGTK4.1, libusb / P |
| Voxtype | Verified stable official DEB; compatible existing APT retained | Refresh or retained APT; no self-updater selected | 1.1+; Wayland/backend/uinput checks / R, K |
| dotool | Pinned verified source built into local DEB; existing APT retained | Pin + common rebuild/refresh or retained APT | 1.6+; Go modules checked, no driver change / P, K |
| Dictation models | Selected official Voxtype model acquisition; existing model IDs/files retained | Manual explicit model acquisition; not an app update | New base.en or GPU-gated Parakeet; model compatibility / P, K |
| Parakeet CUDA13/cuDNN9 | Scoped NVIDIA ubuntu2604 runtime-only APT allowlist | APT; no self-update selected; driver packages excluded | AVX-512, driver 580+, CUDA13/cuDNN9 ABI, sm70–sm120 / M |
| Ollama (optional GPU app) | Compatible native or verified official stable archive | APT or Refresh; no Linux in-app updater selected | 0.40+; working CUDA or physical Vulkan1.2+ GPU / N, R |
| Ollama model/provider lists | Existing Ollama model store; generated harness profiles | Manual `ollama pull/rm`; daily regenerates profiles only | Existing model/provider ownership / K |
| NVIDIA drivers (opt-in) | Ubuntu recommendation, or retained native/manual/IT driver family | Native APT or existing vendor/IT; no replacement | Explicit install preference, signed running-kernel modules preferred / M |
| Zoom (work) | Official GPG-signed vendor DEB/checksums | Verified vendor Refresh; availability/download link is not installation | 6.7.5+; native Wayland experimental / R |
| Slack (work) | Scoped signed vendor APT | APT; Linux package update instructions | 4.35.121+ / V |
| Chrome (work) | Scoped signed Google APT | APT; Linux package owner, not browser About-page replacement | Normalized command/desktop / V |
| Steam (personal) | Native installer and i386 runtime dependencies | APT bootstrap/dependencies **plus genuine Valve client updater** | Official Ubuntu multiverse/i386 indexes; no alternate bootstrap / N |
| Discord (personal) | Verified official DEB Rust bootstrap; existing compatible Snap retained | Genuine Rust client updater on launch; retained Snap refresh | Bootstrap1.0+; old manual-update-only DEB fails / K |
| Firefox (personal) | Signed stable user archive if absent; stock Snap/bootstrap/scoped Mozilla APT retained | Genuine in-app user updater; retained Snap/APT package owner | Writable runtime + exact-path Mozilla AppArmor sandbox attachment / K |
| Mullvad VPN (personal) | Scoped signed official APT | APT; no complete safe Linux self-updating source established | Existing VPN/account/connection policies retained / V |
| just / mkcert (devcontainer) | Native `just`, `mkcert` | APT; no self-update selected | Host recipes/certificate generator / N |
| DNS / certificate utilities (devcontainer) | Native `bind9-dnsutils`, `libnss3-tools` | APT; no self-update selected | dig/certutil; systemd-resolved policy retained / N |
| OpenVPN3 (devcontainer) | Native `openvpn3-client` | APT; no self-update selected | Native resolute source; existing VPN owner / N |
| GNOME / Tweaks / Characters / dconf inspector / base extensions | Installed GNOME50; native `gnome-tweaks`, `gnome-characters`, `dconf-editor`, `gnome-shell-extensions` | APT; no self-update selected | GNOME50 accepted target; Ubuntu installed-desktop prerequisite / N |
| GPaste / tray | Native `gpaste-2`, `gnome-shell-extension-gpaste`, `gir1.2-gpaste-2`, `gnome-shell-ubuntu-extensions` | APT; extension/content refresh is not GNOME binary self-update | GNOME-compatible metadata/schema; Ubuntu tray UUID / N |
| Pop Shell / No Overview / Dash to Panel | Reviewed System76/fthx pins / Dash v74 digest | Pin + setup/sync; extensions do not self-update app binaries | Declared shell compatibility; Pop supports 50–51; only skip above51 accepted / P |
| Power / audio / lid / USB-wake dependencies | Native power-profiles-daemon, existing PipeWire/WirePlumber/systemd/udev | APT or existing IT owner; no self-update selected | Existing providers/masks/policies retained / N, M |
| Adwaita Sans / Noto / Emoji / Liberation / fontconfig | Native font packages listed above | APT; no self-update selected | Exact shared font families / N |
| Adwaita Mono | Verified GNOME49 font archive | Pin + font setup/sync | Exact unpatched Adwaita Mono / P |
| JetBrainsMono / MesloLGS / Ubuntu / FiraCode / Hack Nerd Fonts | Verified Nerd Fonts3.5.1 archives | Pin + font setup/sync | Exact Nerd Font families, not plain variants / P |
| Catppuccin GTK / Papirus overlay / bat theme | Verified GTK1.0.3/overlay/theme pins; native Papirus/base bat preferred | Pin + relevant setup/sync; native base APT | GTK frozen archive; existing user themes retained / P, K |
| NinjaOne / SentinelOne (opt-in/existing IT only) | Vendor native DEB or retained managed enrollment | Genuine vendor agent/patcher updater; weekly health, no bootstrap enrollment | Existing enrollment/security owner; separately authorized removal / M |

All required apps fail on missing incompatible owners. GNOME50 is the accepted
platform target; only incompatible Pop Shell above51 has the accepted feature gap.
Drivers/security agents, APT holds, Snap holds and disabled app settings retain
policy ownership. Recurring checks do not launch desktop apps or enable their
updaters. Full sync applies reviewed pins; daily/weekly do not claim pinned data,
manual toolchains, gems, Composer, in-app updates or downloaded models were refreshed.

`sync.sh --cleanup` previews orphans plus Arch-only obsolete candidates.
`--remove-obsolete` is Arch-only and additionally needs a terminal, typed `remove`
and the native prompt; `--yes` is insufficient. Native orphans require the separate
`dfa-remove-orphans --remove` request. npm packages/stale user configurations remain
intact. No source migration/removal is an updater fallback.

Validation for this final audit: direct Bash syntax, ShellCheck and Python static
parsing only. Updated supplied-fact decision checks are written **unrun**. Native
transactions, vendor installers, profile loading, genuine future updater integrity,
GUI launches, Ubuntu dependency resolution, sandbox enforcement and hardware/model
behavior remain **unverified**. Read-only primary research establishes documented
mechanisms and initial-verification feasibility, not workstation runtime success.
