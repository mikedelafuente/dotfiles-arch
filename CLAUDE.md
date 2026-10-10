# Repository agent guidance

`AGENTS.md` links here. Shared guidance for Claude Code, Codex, Pi and Cursor.
Arch Linux / installed Ubuntu 26.04 LTS, x86_64/amd64, GNOME Wayland workstation.

## Read when relevant

- Deployment, migration, source moves, rollback or daily ordering:
  [docs/deployment.md](docs/deployment.md).
- Packages, acquisition and update owners: [PACKAGES.md](PACKAGES.md).
  Ubuntu source decisions: [source audit](docs/ubuntu-source-update-audit.md).
  Runtime evidence and limits: [integration inventory](docs/ubuntu-integration-validation.md).
- User commands, shortcuts and flows: [README.md](README.md), [REFRESHER.md](REFRESHER.md).
- Script conventions: [.cursor/rules/setup-scripts.mdc](.cursor/rules/setup-scripts.mdc).
  Documentation requirements: [.cursor/rules/docs-and-commands.mdc](.cursor/rules/docs-and-commands.mdc).
  Platform/config rules: [.cursor/rules/dotfiles-arch.mdc](.cursor/rules/dotfiles-arch.mdc).
- Issues: [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md).
  Triage: [docs/agents/triage-labels.md](docs/agents/triage-labels.md).
  Glossary/ADRs: [docs/agents/domain.md](docs/agents/domain.md).

## Shared source and deployment

- Before shared edits, run `dfa-deploy source`; edit only the verified checkout.
  Missing source/provenance: stop shared edits and restore/rebind. For extra sources,
  use `dfa-deploy source --source-id ID`. Installed copies are never source checkouts.
- Runtime links use `~/.local/share/workstation/config`, pointing to `blue` or `green`.
  Deploy replaces installed edits from source, validates before activation and keeps one backup.
  Machine-local settings stay outside managed files. No automatic merging, override or capture.
- Verify using temporary fixtures. Implementation does not authorize deployment,
  migration, package changes, services, GNOME/driver changes or VM operations on this workstation.

## Implementation rules

- Scripts must be idempotent: sync re-runs every setup. Reuse existing helpers.
- Setup scripts source `dotheader.sh` → `fn-lib.sh`; use `USER_HOME_DIR`, including under sudo.
  Installed helpers in `home/.local/bin/` resolve runtime through `dotfiles-arch-lib.sh`
  before loading scripts. Source operations use deployment provenance.
- Saved settings use only `load_bootstrap_config` / `write_bootstrap_config`.
  Profiles are additive (`work`, `personal`, `devcontainer`); `SETUP_PROFILES` stores
  selections, `SETUP_PROFILE` stays the compatible primary. Honor `MACHINE_TYPE`;
  use hardware fallback when unset. `DEFAULT_HARNESS` replaces legacy `DEFAULT_AGENT`.
- Detect unsupported hosts before writes. Disk provisioning and AUR are Arch-only.
- Native packages: `native_package_installed` / `ensure_native_pkgs`, then verify
  required executables/capabilities. Prefer compatible native packages, scoped official
  vendor APT sources, then verified recipes with explicit update owners.
- AUR: `ensure_yay_installed` / `ensure_yay_pkgs` with IoC scanning; fail closed.
  No raw AUR install bypasses or `curl | bash`. Preserve installed owner, driver flavor,
  managed agents, holds/pins, update policies and automatic security updates.
- Link only absent or repository-owned targets. Preserve foreign files/links and report conflicts.
  Git identity stays in real machine-local `~/.gitconfig`; shared settings use `config/git/config`.
  Never append PATH edits to shared `home/.bashrc` from setup scripts.
- Required setup/link/hook/update failures reach final status. Keep child Bash errexit;
  mutation helpers need explicit return/exit guards when callers capture statuses.
  Write successful update stamps only after all requested native/app updates succeed.
- Cleanup previews first. Removal requires a terminal and typing `remove`; `--yes` alone
  never authorizes it. NinjaOne is separate work-profile opt-in; installer URLs are secrets.
- `prepare-archinstall.sh` is live-ISO-only. Require repeated disk-path confirmation;
  exclude nonphysical disks. Never read/write `user_credentials.json`.

## Ownership and orchestration

- Setup order lives only in `scripts/run-profile-setup.sh`: upgrade → setup → links →
  post-link hooks. `setup-dev.sh` runs last so harness selection sees installed tools.
- `dfa-weekly` delegates daily work to `dfa-daily`. Keep the daily deployment restart
  bounded to one; do not duplicate it. Preserve cooldowns and schema stamps.
- [Standalone skills/Pi owner](https://github.com/mikedelafuente/skills) owns portable
  skills/rules/resources and all Pi installation/update/repair/removal/settings.
  This repo owns generic launching and registered-source syncing; no automatic acquisition.
- Primary `skills/` and `rules/` are empty override slots; `.cursor/rules/` is project-only.
  Registered sources must exist. Primary content wins, but protected skill duplicates
  block before mutation unless losing sources allow overwrites. Sync never executes source scripts.
- New harness IDs/labels must agree in `scripts/fn-lib.sh` and
  `home/.local/bin/dotfiles-arch-lib.sh`. Reuse shared default-harness resolution for launchers.

## Migrations and documentation

- Helper renames ship an idempotent `migrations/vN-to-vM-migration.sh`: remove only
  dangling legacy links, then relink. Preserve real files and resolving foreign links.
  Repo schema derives from migration filenames; stamp only successful steps.
  `--dry-run` makes no writes; `--rerun-all` is workstation work, never a validation command.
- Document changed commands/aliases/shortcuts/packages in the same change, following
  the documentation rules above. User entry points include `home/.welcome.md`, `aliases()`,
  `README.md` / `REFRESHER.md`, and `PACKAGES.md`.
  Keep `DFA_COMMANDS` aligned with helper behavior and `ESSENTIAL_PACKAGES` with the package catalog.

## Verification and Git

- Shell changes: `bash -n <paths>` and `shellcheck -x <paths>`; CI uses `scripts/check.sh`.
  Run relevant decision checks with supplied facts and temporary state. Report unrun checks.
- Work on a feature branch; never commit directly to `main`.
  After merging, delete local/remote feature branches and return to clean `main`.
- Answer briefly: result first, commands/paths in inline code, no filler.
  Shared style: [skills owner](https://github.com/mikedelafuente/skills/tree/main/rules).
