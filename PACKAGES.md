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
on x86_64/amd64. Full Ubuntu bootstrap/sync stays guarded pending other slices.

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
26.04 on amd64/x86_64. Full Ubuntu bootstrap/sync remains guarded.

| App / commands | Arch source | Ubuntu 26.04 source | Minimum / update owner |
|----------------|-------------|---------------------|------------------------|
| Neovim / `nvim`, `v`, `vim`, `dev --tmux` | Compatible native `neovim` preferred | Native 0.11.6 is insufficient; missing installs use [official stable archives](https://github.com/neovim/neovim-releases/releases) | **0.12.0+**; native updater or managed upstream refresh via `dfa-update-system` |
| Treesitter / `tree-sitter`, `:TSUpdate` | Compatible native `tree-sitter-cli` preferred | Native 0.25.9 is insufficient; missing installs use [official stable releases](https://github.com/tree-sitter/tree-sitter/releases) | **0.26.1+**; native updater or managed upstream refresh via `dfa-update-system`; never npm |
| tmux / `tmux`, `dev --tmux` | Native `tmux` | Native `tmux` | **3.2+**; native updater |
| Git TUI / `lazygit`, `lzg` | Native `lazygit` | Native Universe `lazygit` | **0.40+**; native updater and existing core CLI ownership checks |
| Container TUI / `lazydocker`, `lzd` | [Arch Extra `lazydocker`](https://archlinux.org/packages/extra/x86_64/lazydocker/) | Compatible native candidate if available, otherwise [verified official releases](https://github.com/jesseduffield/lazydocker/releases) | **0.20+**; native updater or managed upstream refresh via `dfa-update-system` |
| Build/archive/TLS helpers | `gcc`, `make`, `tar`, `gzip`, `unzip`, `ca-certificates` | Same native names | Native updater; parser/native-plugin builds and verified downloads |
| Python provider / Mason tools | `python`, `python-pynvim`, `python-pip` | `python3`, `python3-pynvim`, `python3-pip`, `python3-venv` | Native updater; Ubuntu virtual environments respect externally managed system Python |
| Search/Git/hooks/clipboard | `fd`, `ripgrep`, `git`, `curl`, `jq`, `wl-clipboard`, `xsel` | `fd-find` plus executable `fd` link; remaining names match | Existing core CLI/native updater; `jq` supports reveal-hook payloads |
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
Full Ubuntu orchestration and the remaining app matrix are subsequent slices.

### Maintenance distro slice

Implemented for [#142](https://github.com/mikedelafuente/dotfiles-arch/issues/142).

| Installed apps / host | App source | Update owner |
|-----------------------|------------|--------------|
| Native system packages, including Kitty / Arch | Existing official pacman repositories | `dfa-update-system`: pacman, then guarded AUR updates |
| AUR apps / Arch | Existing AUR recipes, including their AUR dependencies | `yay -Sua` after an IoC scan; query/scanner/metadata failures fail closed |
| Native packages, including Kitty / Ubuntu 26.04 | Existing configured Ubuntu and vendor APT repositories | `dfa-update-system`: APT refresh and upgrade with new dependencies permitted, removals refused |
| Existing npm-installed Claude / Codex / Pi / either host | User-level npm packages through NVM | `dfa-update-npm-clis` daily step verifies global package and resolved launcher ownership; no root npm |
| Existing native Claude / either host | Official user-native launcher into `USER_HOME_DIR/.local/share/claude/versions/<version>` | `dfa-update-npm-clis` runs `claude update` as the user, independently of NVM/npm; native background updates also remain enabled according to user settings |
| NinjaOne / Arch | Existing opt-in repackaged vendor DEB | Agent self-updater plus existing weekly health check |
| Managed NinjaOne / Ubuntu | Existing IT-selected source | Existing vendor/IT owner; weekly Arch repair is policy-deferred until native lifecycle conversion |

No package or software source is installed by this slice. It adds no vendor
repository, signing key, source fallback, app migration, or duplicate installation.
APT keeps existing holds/pins and source priorities; source conflicts remain for
the source owner to resolve. Standalone DEBs/archives without a configured update
repository are **not** made updateable by this change; their recipes/owners remain
subsequent app slices. Recognized native Claude uses its own updater; other
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
handles NinjaOne (policy-deferred on Ubuntu). User-only sync steps are allowed on
Ubuntu; full bootstrap/sync and historical Arch setup migrations remain guarded.
If daily auto-resync requests full Ubuntu setup, that failure stays in its summary.
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
| Arch `python`, `python-pip`, `python-pynvim`; Ubuntu `python3`, `python3-pip`, `python3-venv`, `python3-pynvim`, `python3-dev` | `setup-python.sh` | Interpreter, pip, venv/ensurepip, Neovim provider, native extension headers | `py`, `pip`, `serve`, `jsonpp` |
| Arch `go`, `gopls`; Ubuntu `golang-go`, `gopls` | `setup-golang.sh` | Go compiler, standard library, language server | `go`, `gopls` |
| `rustup` (both distros) | `setup-rust.sh` | User Rust toolchain manager; compatible existing distro Rust is retained | `cargo`, `rustc`, `rustup` |
| Arch `ruby`, `sqlite`, `base-devel`; Ubuntu `ruby`, `ruby-dev`, `sqlite3`, `libsqlite3-dev`, `build-essential`, `libyaml-dev` | `setup-ruby.sh` | Ruby/RubyGems, Ruby headers, Rails database, native gem compilation and YAML headers | `ruby`, `gem`, `bundle`, `rails` |
| Arch `php`, `php-gd`, `php-intl`, `php-sqlite`, `php-pgsql`, `composer`; Ubuntu `php-cli`, `php-curl`, `php-gd`, `php-intl`, `php-mbstring`, `php-xml`, `php-mysql`, `php-sqlite3`, `php-pgsql`, `composer` | `setup-php.sh` | PHP CLI, HTTP/image/Unicode/XML extensions, MySQL/SQLite/PostgreSQL drivers, Composer and user Laravel installer | `php`, `composer`, `laravel` |
| Arch `base-devel`, `openssl`, `zlib`, `libffi`, `libyaml`, `pkgconf`, `sqlite`; Ubuntu `build-essential`, `libssl-dev`, `zlib1g-dev`, `libffi-dev`, `libyaml-dev`, `pkg-config`, `sqlite3`, `libsqlite3-dev` | All five language setups | C/C++ compiler/linker/make, TLS/compression/FFI/YAML headers, library discovery, SQLite CLI/headers for native builds | `cc`, `make`, `pkg-config`, `sqlite3` |
| NVM + Node LTS (not pacman) | `setup-node.sh` | Node via NVM at `~/.config/nvm` | `nvm`, `node`, `npm` |
| Claude Code (user-level npm) | `setup-claude.sh` | Claude Code CLI | `claude` |
| Codex CLI (user-level npm, `@openai/codex`) | `setup-codex.sh` | OpenAI Codex CLI | `codex` |
| `chatgpt-desktop` (AUR) | `setup-codex.sh` | ChatGPT desktop app (repackaged official binary) | `chatgpt` |
| `opencode` | `setup-opencode.sh` | AI coding agent CLI | `opencode` |
| `ollama-cuda` / `ollama-vulkan` (GPU-gated) | `setup-ollama.sh` | Local model server — `ollama-cuda` on a working NVIDIA driver, else `ollama-vulkan` on a detected Vulkan ICD; skipped entirely (no CPU-only install) if neither is present | `ollama` |

### Shared language sources and update owners

The five standalone language setups support rolling Arch and Ubuntu 26.04 amd64.
They use the existing native backend, without vendor repositories, AUR additions,
runtime managers replacing native Python/Go/PHP/Ruby, or root-owned user installs.
Full Ubuntu bootstrap/sync is still guarded pending the remaining app slices.

| Component | Source / retained installation | Update owner | Compatibility / configuration |
| --- | --- | --- | --- |
| Python | Native distro packages above | `dfa-update-system`; project dependencies use the project's venv/pip | Python 3.10+; import pip, venv, ensurepip and pynvim; native-owned `pip3`. No system pip installs or externally-managed override. |
| Go / gopls | Native packages above | `dfa-update-system` | Go 1.24+, gopls 0.16+; compiler tool and standard-library directories must exist. Go's optional automatic toolchain selection is left unchanged. |
| rustup binary | Native `rustup` preferred for new setups; existing user rustup retained | Native binary: `dfa-update-system`; user binary: manual `rustup self update` | Rustup proxies must share the manager's file identity. Existing user `CARGO_HOME`/`RUSTUP_HOME` remain user-owned; no pipe-to-shell installer. |
| Rust / Cargo | User toolchains via rustup, or compatible existing distro Rust/Cargo | Rustup toolchains: manual `rustup update`; distro toolchain: `dfa-update-system` | Rust/Cargo 1.70+ baseline. Stable is initialized only with no selected default/toolchain; existing pinned, beta/nightly defaults and `RUSTUP_TOOLCHAIN` are retained. No distro rustup self-update. |
| PHP / Composer | Native distro packages above | `dfa-update-system` | PHP 8.2+, Composer 2+; Laravel-required builtins/extensions and GD/Intl/MySQL/SQLite/PostgreSQL are checked. Arch enables exact missing directives in shared `/etc/php/php.ini`; Ubuntu enables missing modules with `phpenmod -v <major.minor> -s cli`, using `/etc/php/<major.minor>/cli/{php.ini,conf.d}` and leaving web server SAPIs unchanged. |
| Laravel installer | Composer global package in the existing user Composer home/bin-dir | Manual `composer global update laravel/installer` | Preserve `COMPOSER_HOME`/global bin-dir; verify the installer command. Shell PATH includes XDG/explicit Composer homes and legacy `~/.composer/vendor/bin`; custom bin-dir must already be on PATH. |
| Ruby / native headers | Native distro packages above | `dfa-update-system` | Ruby 3.2+; RubyGems, OpenSSL and Psych must work; NVM Node is required for the existing Rails JS workflow. |
| Bundler / Rails | User gems (`gem install --user-install`) or compatible existing native commands | User gems: manual `gem update --user-install <user-gem> --no-document` (`bundler` or `rails` only when user-owned); native gems: `dfa-update-system` | Use RubyGems' actual `Gem.user_dir`, not a hardcoded Ruby ABI. PATH covers XDG `gem/ruby/*/bin` and legacy `~/.gem/ruby/*/bin`; verify `bundle` and `rails`, even when a gem is listed. Never `sudo gem` or `gem update --system`. |

Manual toolchain/gem/Composer updates retain the existing opt-in workflow; daily
native updates do not claim to refresh them. All package, rustup, gem and Composer
mutation failures exit nonzero before setup completion; these setups write no
successful-update stamps. Native update stamps retain the shared backend's failure
contract. User tooling is rejected when run as root. Unknown/shadowing launchers,
unowned alternatives, unsupported versions, custom PHP config overrides, and
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
support the configuration choices. Runtime floors are workflow baselines, not version
pins or permission to upgrade an incompatible existing runtime silently.

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
| `voxtype-bin` (AUR), `dotool` (AUR) | `setup-voxtype.sh` | Voice-to-text dictation — Super+T toggles |
| `cuda`, `cudnn` (on working NVIDIA driver only) | `setup-voxtype.sh` | CUDA runtime + cuDNN shared libs for voxtype's Parakeet/ONNX Runtime GPU backend |
| `zed` | `setup-zed.sh` | Code editor |
| `stably-orca-bin` (AUR) | `setup-orca.sh` | [Orca](https://www.onorca.dev/), an IDE for parallel coding agents; launch with `stably-orca` (the `orca` package is the GNOME screen reader) |
| `zsa-keymapp-bin` (AUR) | `setup-moonlander.sh` | ZSA Moonlander keyboard flashing |

## Profile extras

Profiles are **additive multi-select** — enable any combination on one machine
(`SETUP_PROFILES`, e.g. `work devcontainer`). Shared stack always installs first.

### work — `setup-zoom.sh`, `setup-slack.sh`, `setup-chrome.sh`

| Package | Purpose | Related commands |
|---------|---------|-------------------|
| `zoom` (AUR) | Meetings | — |
| `slack-desktop` (AUR) | Team chat | — |
| `google-chrome` (AUR) | Work browser (Super+B when work is selected) | — |
| `ninjaone-agent` (local, repackaged vendor `.deb`) | NinjaOne MDM/endpoint agent; installed once with `dfa-install-ninjaone` (not part of `sync.sh`), health-checked by `dfa-weekly` | `dfa-install-ninjaone`, `dfa-update-ninjaone` |

### personal — `setup-steam.sh`, `setup-discord.sh`, `setup-firefox.sh`, `setup-mullvad.sh`

| Package | Purpose | Related commands |
|---------|---------|------------------|
| `steam` (multilib) | Games | — |
| `discord` (AUR) | Chat | — |
| `firefox` | Personal browser (Super+B when personal is selected and work is not) | — |
| `mullvad-vpn-bin` (AUR) | VPN | `mvup`, `mvdown`, `mvst` |

### devcontainer — `setup-devcontainer.sh`

Host prerequisites for the platform / work devcontainer sandbox.
Docker and GitHub CLI are already on the shared stack; this profile adds
the rest of the host checklist (tools, DNS, watches, CA trust).

| Package / config | Purpose | Related commands |
|------------------|---------|------------------|
| `just` | Host lifecycle recipes in the devcontainer repo | `just`, `just --list` |
| `mkcert` | Local TLS CA + certs for project `*.test` domains | `mkcert -install` |
| `nss` | Firefox/trust-store support used by mkcert | — |
| `bind` | `dig` for DNS smoke checks to port 5354 | `dig @127.0.0.1 -p 5354 …` |
| `openvpn3` (AUR) | OpenVPN 3 Linux client (CloudConnexa / work VPN). Official docs only cover apt/dnf; AUR ships the same `openvpn3-linux` project. | `openvpn3 config-import`, `session-start`, `sessions-list`, `session-manage` |
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
| Zed / `zed`, `zeditor`, `dev` | Official Extra `zed`; only this transition removes legacy `~/.local/zed.app` | Verified official stable amd64 archive at `~/.local/zed.app`; retain recognized compatible native/user installs | pacman/APT for native; Zed's in-app self-updater for user installs (must stay enabled) |
| Stably Orca / `stably-orca`, `orca-ide` | IoC-scanned `stably-orca-bin` AUR | Verified official amd64 AppImage in `~/.local/share/dotfiles-arch/orca/Orca.AppImage`; `libfuse2t64` supplies FUSE2 | Guarded AUR on Arch; AppImage's in-app self-updater on Ubuntu (must stay enabled) |
| Existing Ubuntu `orca-ide` DEB | — | Preserve the installed package instead of replacing it with an AppImage | Verified official stable DEB refresh through `dfa-update-system`; in-app notifications alone do **not** install updates |

Favor true self-updating user installations on Ubuntu. Existing compatible sources
retain their owners. AppImage replacements keep the fixed pathname so command
links and desktop entries survive. No `orca` alias is created: that name belongs
to GNOME's screen reader. No installer script, PPA, foreign APT suite, source
fallback, sandbox bypass, or driver replacement is added. Full Ubuntu orchestration
is still guarded pending the other application slices; these two standalone setup
scripts are enabled.

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
| Claude Code | User npm `@anthropic-ai/claude-code`; retain recognized user-native installs | Same | `dfa-update-npm-clis`: npm or `claude update`; native background preferences retained |
| Codex CLI | User npm `@openai/codex` | Same | `dfa-update-npm-clis` |
| Pi | User npm `@earendil-works/pi-coding-agent`, lifecycle scripts blocked | Same | `dfa-update-npm-clis`, also with `--ignore-scripts` |
| opencode CLI | Official `opencode` package; retain existing user npm if recognized | Stable user npm `opencode-ai`, documented source exception | Native: `dfa-update-system`; npm: `dfa-update-npm-clis` |
| Selected official ChatGPT desktop | Guarded `chatgpt-desktop` AUR recipe; retain existing official `chatgpt` package | Official `chatgpt` from scoped, signed OpenAI APT repository | `dfa-update-system` (Arch AUR/native or Ubuntu APT) |

[Stable opencode instructions](https://opencode.ai/docs/) document `opencode-ai`
and Arch's native package. This slice retains the `opencode` CLI identity and
existing provider configuration; it does not switch to the beta `opencode2` CLI.
Claude/Codex/Pi retain existing npm sources. Setup/update refuse root invocation
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
is also unverified; upstream calls native Wayland experimental. Full Ubuntu
orchestration and optional Ollama acquisition remain separately guarded slices.
