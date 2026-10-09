# Arch and Ubuntu workstation support

Analysis recorded 2026-10-08; synthesized into [the implementation spec](specs/arch-ubuntu-workstations.md), published as [#139](https://github.com/mikedelafuente/dotfiles-arch/issues/139). This document records analysis and interview decisions; distro support has not been implemented or validated on Ubuntu.

## Accepted requirements

- One repository: rolling Arch and Ubuntu 26.04 LTS, both with GNOME.
- Same selected applications, commands, configuration, and workflows; compatible versions may differ.
- All current additive profiles: work, personal, devcontainer.
- Ubuntu starts from an installed desktop, with sudo and external software sources permitted.
- Shared setup/configuration; small native package backends and explicit per-app acquisition recipes.
- Prefer compatible distro packages, then official vendor APT repositories. Document other formats as exceptions; avoid silent source fallback and duplicate installations.
- Preserve work-managed drivers/security agents and Ubuntu automatic security updates.
- Keep `dfa-daily`, `dfa-weekly`, bootstrap, and sync as common entrypoints.
- Incompatible extensions require a reported feature gap and an explicit exception; do not force-load them.
- Update failures must return nonzero and cannot write a successful-update stamp. Daily unattended updates exclude removals and release upgrades.
- Validation must not change the operating system: use read-only decision checks and static analysis, and disclose unverified installation/update/desktop/hardware behavior. Do not execute mutating setup commands or provision VMs as tests.

See [ADR 0002](adr/0002-shared-arch-ubuntu-workstations.md) and [the glossary](../GLOSSARY.md).

## Repository findings

41 setup scripts exist; 31 mention pacman and 16 invoke `ensure_yay_pkgs`. Package operations also bypass shared helpers, so changing `fn-lib.sh` alone cannot port the repo.

| Area | Existing seam or required change |
| --- | --- |
| Profiles/configuration | Reuse `run-profile-setup.sh`, `link-dotfiles.sh`, NVM/npm tooling, and user configuration. |
| Package lifecycle | Replace direct distro assumptions in install/status/remove/update operations and both bootstrap/sync orchestrators. Keep AUR scanning Arch-only. |
| Executable identity | Ubuntu `fd-find` and `bat` use `fdfind` and `batcat`; preserve commands used by scripts and editor configuration, not only interactive aliases. |
| Zed | Current cleanup removes the official upstream user installation; restrict that cleanup to its Arch package migration. Normalize `zeditor`/`zed` launchers. |
| Neovim | LSP config uses 0.11+ APIs, but the pinned Treesitter plugin requires Neovim 0.12+ and tree-sitter CLI 0.26.1+. Ubuntu's 0.11.6/0.25.9 tools require a source exception or a shared plugin compatibility pin. |
| GNOME | Validate extensions against the installed shell and guard optional schemas. Check Ubuntu default extensions for conflicts with the shared panel/shortcuts. |
| System configuration | PHP paths, NVIDIA packages, GPU runtimes, font acquisition, Docker dependencies, and NinjaOne packaging need distro-specific handling. |
| Maintenance | Existing cooldown stamps are Arch-named; port their semantics and preserve existing Arch state. Some updater/setup failures currently get swallowed. |
| Validation | Current CI runs syntax/ShellCheck on Ubuntu; it does not execute workstation setup or prove app/desktop parity. |

`safe_system_upgrade` currently leaves pacman/yay exit statuses unchecked before a final success print (`fn-lib.sh`). Conditional callers can therefore record success after a failed upgrade. Correct this at the shared update boundary, with a regression check, while preserving the AUR fail-closed scan.

## Initial source feasibility

These are candidates, not final selections or runtime guarantees. Every selected app still needs an install/update entry in the eventual package catalog.

| App or component | Ubuntu candidate | Update owner and evidence |
| --- | --- | --- |
| Neovim/Treesitter | Newer upstream tools or a compatible shared plugin pin | [26.04 Neovim is 0.11.6](https://packages.ubuntu.com/resolute/amd64/neovim), below the [pinned Treesitter requirement](https://github.com/nvim-treesitter/nvim-treesitter/blob/8b98b4470eb326f1c7b50dae79f8c963568e5720/README.md). Source/update strategy pending. |
| Docker Engine/Compose/Buildx | Official vendor APT repository | APT; [Docker lists Ubuntu 26.04](https://docs.docker.com/engine/install/ubuntu/). |
| TablePlus | Official 26.04 APT repository | APT; [vendor provides 26.04 repositories](https://tableplus.com/download/linux). Scope signing keys to this repository. |
| OpenVPN3 | Ubuntu `openvpn3-client`, or vendor APT if needed | APT; [upstream lists 26.04 and distro availability](https://community.openvpn.net/Pages/OpenVPN3Linux). |
| Zed | Official user tarball installation | App self-updater; [installation](https://zed.dev/docs/linux), [updates](https://zed.dev/docs/update). Verify Vulkan and CLI compatibility. |
| Orca, Stably IDE | Official AppImage or DEB | [AppImage self-updates; DEB only notifies](https://www.onorca.dev/docs/install). Normalize `orca-ide` versus existing `stably-orca`. |
| Voxtype | Official release DEB | Repo-managed release refresh needed; [upstream declares Ubuntu 24.04+](https://voxtype.io/docs/). GNOME `dotool` dependency remains unresolved. |
| Obsidian | Official DEB or documented alternative | [In-app updates and installer updates differ](https://obsidian.md/help/updates); native DEB needs a separate installer-refresh path. |
| Ollama | Official Linux archives and service | Repo-managed archive refresh; [upstream Linux instructions](https://docs.ollama.com/linux). Verify working GPU/backend separately. |
| GNOME extensions | Compatible packaged/upstream versions | Ubuntu 26.04 uses [GNOME 50](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/). GPaste's [Ubuntu changelog](https://changelogs.ubuntu.com/changelogs/pool/universe/g/gpaste/gpaste_45.3-5/changelog) declares GNOME 50 support; desktop behavior still needs testing. |

Do not assume a locally installed DEB gets future updates from APT unless a repository publishes them. Do not treat installing an app as proof its configured workflow works. Generic Linux support is not release-specific Ubuntu validation.

## Unanswered interview choices

- Initial CPU architecture coverage.
- Handling pre-existing applications from a different source, including IT-managed installations.
- Confirmation rules for weekly orphan removal and Ubuntu upgrades that need package removals.
- Neovim/plugin compatibility strategy, Docker provider, and GNOME extension update ownership.
- Completion criteria, validation environments, and whether explicitly accepted feature gaps can ship.

The requested spec synthesis proceeds without another interview. The spec explicitly labels conservative defaults for unanswered choices; the later user instruction excludes OS-changing tests and replaces the proposed live/VM validation gate.

## Proposed implementation order

1. Add distro detection and native package lifecycle operations, including explicit failure propagation. Prove Arch behavior and Ubuntu dispatch with isolated checks.
2. Port bootstrap/sync/update/cleanup consumers and the CLI/development stack. Preserve config paths and command names.
3. Complete the per-app source/update catalog and port remaining desktop apps, fonts, GNOME configuration, and hardware-specific branches.
4. Validate read-only selection/version/removal decisions and static script correctness without executing OS-changing workflows. Inventory unverified fresh setup, idempotency, update, desktop, and hardware behavior; do not claim runtime app parity from static checks.

The published spec is the implementation handoff. No package installations or setup scripts were run during this analysis or spec synthesis.
