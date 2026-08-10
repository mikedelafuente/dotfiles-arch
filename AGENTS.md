# AGENTS.md

Arch Linux workstation dotfiles: GNOME (Wayland), Kitty, Herdr, Neovim, Cursor, Claude Code.
Bash scripts plus symlinked configs — no build system, no test suite.

## Before you change anything

- Architecture and script behavior: [CLAUDE.md](CLAUDE.md)
- Why a package is installed: [PACKAGES.md](PACKAGES.md)
- User-facing flows and shortcuts: [README.md](README.md) · [REFRESHER.md](REFRESHER.md)
- Enforced conventions: [.cursor/rules/](.cursor/rules/)
  - `dotfiles-arch.mdc` — stack, orchestration, bootstrap config keys, AUR safety
  - `docs-and-commands.mdc` — where every new command/alias/shortcut/package gets documented
  - `setup-scripts.mdc` — script header, idempotency, package helpers

## Non-negotiables

1. Read/write saved settings only via `load_bootstrap_config` / `write_bootstrap_config`
   (`FULL_NAME`, `EMAIL_ADDRESS`, `SETUP_PROFILES` multi-select, `SETUP_PROFILE` primary,
   `INSTALL_NVIDIA`, `MACHINE_TYPE`).
2. Use `USER_HOME_DIR`; machines have different usernames.
3. No new `curl | bash` installers; AUR goes through the IoC-scanning helpers.
4. Scripts must be safe to re-run — `sync.sh` runs all of them every time.
5. Document new user-facing commands in `home/.welcome.md`, `aliases()`, and `PACKAGES.md`.

## Verify

```bash
bash scripts/check.sh   # bash -n + shellcheck -x (same as CI)
```
