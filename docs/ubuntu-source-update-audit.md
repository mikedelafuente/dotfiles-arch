# Ubuntu source and updater audit

Evidence reviewed 2026-10-09 for [#162](https://github.com/mikedelafuente/dotfiles-arch/issues/162).
The [final source/update matrix](../PACKAGES.md#final-ubuntu-source--update-audit)
records every selected shared/work/personal/devcontainer application and the
opt-in endpoint-agent boundary. Per-family package tables there contain the
existing source pins, package purposes and detailed compatibility contracts.
This audit adds no second executable application registry.

## Source preference and preserved ownership

For a missing Ubuntu application, select a verified compatible complete
self-updater when one exists. This pass selects native Claude, Mozilla user
Firefox, user rustup and Composer PHAR; already-selected user Zed, Orca AppImage,
Discord's Rust bootstrap and Steam's split client owner remain. Compatible
installed npm/Snap/APT and marked user sources retain their owners. A hidden
second package/tree or conflicting launcher is a conflict, not permission to
migrate. Unknown manually installed software is retained with an owner diagnostic.
Arch retains its native/AUR rules and scanned AUR dependencies.

A genuine updater downloads and replaces executable application code, either
in the background or through an explicit app command. Package-manager refreshes,
notifications, update download links and rerunning an installer are separate
owners. A parser/model/page-cache refresh does not update the host application.
A runtime that cannot update alongside application code needs a second owner.

## Initial integrity and genuine updater evidence

[Claude's official setup](https://code.claude.com/docs/en/setup) describes the
user-native launcher, background replacement and `claude update`. New Ubuntu
setup reads the stable version, validates a detached-signed manifest against
primary key `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`, checks its exact linux-x64
SHA256, then invokes the verified binary's installer with that exact version.
It verifies the resulting binary again. No remote shell script executes, no
`--force` replaces another launcher, and native Claude does not require npm.
Initial signed releases require 2.1.207+ here; the floor also avoids older custom
launcher replacement behavior. Existing official stable/latest scoped APT
installations use APT. Existing npm installations remain user npm. Maintenance
checks source/key/candidate ownership for retained Claude and ChatGPT APT before
and after the native metadata refresh. Server-managed constraints remain enforced
by Claude itself; installer internals and future updater verification were not
executed or independently certified by this audit.

Mozilla documents [user tarball installation](https://support.mozilla.org/en-US/kb/install-firefox-linux)
and [automatic/manual app updates](https://support.mozilla.org/en-US/kb/update-firefox-latest-release).
New absent Firefox uses the exact stable en-US amd64 archive, detached-signed
SHA256SUMS, and Mozilla's [published release key rotation](https://blog.mozilla.org/security/2026/08/10/updated-gpg-key-for-signing-firefox-and-thunderbird-releases/):
primary `14F26682D0916CDD81E37B6D61B7B526D98F0353`. The isolated keyring trusts
only that primary key; bad/revoked/expired signatures fail. Extraction uses
Python's data filter and checks named runtime files plus the application version
before installing a writable tree. Firefox's [MAR documentation](https://firefox-source-docs.mozilla.org/toolkit/mozapps/update/docs/MarFiles.html)
explains signed update archives. Stock Snap, Ubuntu's Snap bootstrap and existing
scoped Mozilla APT remain package-owned; a missing Snap behind its bootstrap is
repaired through that owner rather than supplemented with a user browser.

Ubuntu's user-namespace restriction needs Mozilla's
[AppArmor sandbox attachment](https://support.mozilla.org/en-US/kb/linux-security-warning).
Setup creates only a dedicated profile for this user's exact
`~/.local/share/dotfiles-arch/firefox/{firefox,firefox-bin,updater}` executables.
Like Mozilla's recommendation, its `unconfined` attachment grants `userns` so
Firefox can construct its own sandbox; it is not a general confinement profile.
It does not disable AppArmor, change global namespace restrictions, rewrite
existing vendor/IT profiles or set a browser sandbox-disable flag. Paths containing
AppArmor pattern/injection characters are refused. An existing dedicated file
must match; site policy remains in its optional local include. A missing parser,
profile conflict or failed profile application fails setup before publishing a
new runtime. Only this profile is loaded; maintenance compares its content
without loading profiles or reinstalling the browser. Actual enforcement and
GUI integration remain unverified.

[Rustup's official alternate installation guide](https://rust-lang.github.io/rustup/installation/other.html)
provides the direct amd64 `rustup-init` and HTTPS SHA256 file. Read-only acquisition
confirmed the checksum format `HEX *./rustup-init`; setup accepts that exact
format and verifies before execution. It uses `--no-modify-path` and initializes
no toolchain through the installer, then retains an existing default or explicit
`RUSTUP_TOOLCHAIN`. The [rustup book](https://rust-lang.github.io/rustup/basics.html)
distinguishes `rustup self update` for the user manager from `rustup update` for
its toolchains. These remain manual user actions. Native managers must never
self-update a package-owned executable. Native/user conflicts and nonmatching
Rust proxies fail before another source is installed.

[Composer's download guide](https://getcomposer.org/download/) describes its
SHA384-verified PHP installer and stable PHAR. New Ubuntu Composer validates the
installer against `https://composer.github.io/installer.sig`, runs it staged as
the user, and preserves the installer's PHAR verification/updater keys. The
[CLI reference](https://getcomposer.org/doc/03-cli.md#self-update-selfupdate)
describes true PHAR replacement through `composer self-update`; daily never
runs it. Existing native Composer stays with APT, whose PHP dependency/security
integration is preserved. Neither Laravel dependency updates nor PHP upgrades
are claimed as Composer self-updates. Composer/XDG state is checked to stay
inside the user home before invoking a new installer.

[Zed's updater implementation](https://github.com/zed-industries/zed/blob/main/crates/auto_update/src/auto_update.rs)
replaces Linux user releases. [Orca's official install guide](https://www.onorca.dev/docs/install)
distinguishes self-updating AppImage from DEB/RPM availability notices; retained
Orca DEB uses verified installer refresh. Both initial recipes require official
release SHA256 digests. [Discord's vendor announcement](https://discord.com/blog/discord-patch-notes-may-4-2026)
confirms the Linux Rust updater, replacing its former manual-update prompt.
The verified bootstrap remains package-owned; client releases update on launch.
Steam similarly retains native installer/dependencies plus its Valve client
update owner. These runtime replacement mechanisms were not executed here.

## Exceptions and maintenance boundaries

[Official Codex CLI documentation](https://learn.chatgpt.com/docs/codex/cli)
presents the standalone installer again as the update method. That does not
establish an independently verified complete self-update owner for this recipe;
Codex retains the official user npm package. [Pi's official docs](https://pi.dev/docs/latest)
specify npm acquisition; Pi remains npm-owned with lifecycle scripts disabled.
[OpenCode's implementation](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/installation/index.ts)
shows its curl-method upgrade downloading installer text and piping it to shell,
while npm-method upgrade invokes npm. The command name does not make the former
safe; Ubuntu retains verified user npm rather than selecting a remote-shell owner.

Postman documents a genuine [Linux user-archive updater](https://learning.postman.com/docs/getting-started/installation/troubleshoot)
when its runtime directory is writable. Existing recognized archives retain that
owner. New archives have no established authenticated immutable initial checksum
or signature in this bounded review, so the verified official Snap remains the
bundled-library exception. Snap automatic refresh is store-owned and respects
holds. No explicit refresh or channel switch bypasses a hold.

[Obsidian's update guide](https://help.obsidian.md/updates) separates app-code
updates from installer/Electron replacement. Its ASAR updater is genuine, but
incomplete for maintaining the runtime. The verified official DEB refresh
continues alongside it. Holds defer installer refresh; a newer displayed app
version does not prove a current Electron installer. AppImage packaging alone
does not establish a full-runtime self-updater.

[Chrome's Linux update guidance](https://support.google.com/chrome/answer/95414)
and [Slack's Linux update guidance](https://slack.com/help/articles/360048367814-Update-the-Slack-desktop-app)
retain package-manager ownership. TablePlus, Spotify, Mullvad and Zoom keep their
existing vendor APT or verified-release recipes: no safe compatible complete
Linux user-updating replacement source was established. Spotify's
[generic desktop update page](https://support.spotify.com/us/article/updating-spotify/)
is not evidence that a writable, verifiable Ubuntu user archive exists. Kitty's
[binary installation instructions](https://sw.kovidgoyal.net/kitty/binary/)
rerun an installer; the selected native source retains APT. Release-managed
Neovim/Treesitter/container/GPU tools keep their verified owners;
update notifications, parser/plugin downloads and model pulls are not binary
self-updates. Native host/language/build/runtime packages use APT. Pinned fonts,
themes/extensions builds need maintainer review; full sync applies new
reviewed pins without pretending those assets self-update. The matrix lists all
these exceptions, their alternative owners and compatibility requirements.

## Disabled updates

Background updaters run only when the relevant app runs. Maintenance does not
launch desktop applications, enable updater settings or claim their updates
completed. If user/IT policy disables Firefox, Zed, Orca, Postman, Discord, Steam
or Obsidian updates, maintenance retains the source and reports the owner; the
user/IT must authorize the app's update action or policy change. Do not replace a
disabled updater with another package source. Obsidian's separately authorized
installer owner and native bootstrap dependencies still follow their own holds.

Claude's documented `DISABLE_AUTOUPDATER=1` disables background checks but permits
`claude update`; recurring CLI maintenance is an explicit manual-updater request.
`DISABLE_UPDATES=1` blocks every Claude update path. The CLI dispatcher conservatively
reads inherited environment plus visible user/project/local/managed JSON opt-outs
and reports **policy-deferred**, separately from updated and failed counts. Invalid
visible policy files fail without attempting an update. It never overrides keys,
release channels, minimum/maximum versions or hidden server-managed policy. Native
APT installations retain their package holds/pins; their environment alone is not
an authorization to change APT policy. Rustup/Composer/manual language tools keep
their opt-in command owners; daily/weekly do not update them automatically.

## Validation evidence and remaining runtime gaps

Only direct Bash syntax, ShellCheck and Python AST parsing were run for this
pass. Supplied-fact regression checks for new source/owner/metadata/policy choices
are written but unrun. No setup/update/test scripts, installer binaries, native
transactions, services, AppArmor profile loads, GUI launches, driver/GPU/device
or model workflows, or VMs were executed. Read-only primary research and Rustup
checksum metadata were inspected; published signed metadata feasibility does not
claim installation or future update verification succeeded on a workstation.
Initial download/installer/library behavior, update replacement, AppArmor sandbox
enforcement, launchers/desktop defaults, toolchain/proxy behavior and managed
policy effectiveness remain unverified. GNOME50 is the accepted target; only the
Pop Shell skip above51 (GNOME 51 uses the reviewed compatibility pin) is an accepted feature gap, not another app/source waiver.
