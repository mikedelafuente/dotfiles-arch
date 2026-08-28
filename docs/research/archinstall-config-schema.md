# archinstall `--config` / `--creds` schema check (as of 2026-08-28)

Research task: verify whether the repo's tracked `user_configuration.json`
(archinstall `--config` file) is still valid against the archinstall version
that actually ships today, before writing a companion script that patches
`device` / `hostname` / `gfx_driver` per install.

**Bottom line: still valid, no changes needed.** The tracked file already
matches the archinstall 4.4 schema exactly, field for field, including one
detail (`gfx_driver` value) that would otherwise be a classic
schema-drift trap.

## Current archinstall version

- **4.4** is still the latest release as of 2026-08-28. No 4.5/5.0 has
  shipped.
- GitHub tag `4.4`, published **2026-06-28T20:19:39Z** — confirmed via
  `gh api repos/archlinux/archinstall/releases` (top of the list; next
  newest is `4.3` on 2026-04-20). Source: <https://github.com/archlinux/archinstall/releases/tag/4.4>
- Arch package db: `archinstall 4.4-1` in `extra`, last updated
  **2026-06-28 20:23 UTC**. Source: <https://archlinux.org/packages/extra/any/archinstall/>
- The `archlinux-2026.08.01` monthly ISO (one month newer than the
  `2026.07.01` ISO named in `NOTES.md`) still ships this same archinstall
  4.4. Source: <https://archlinux.org/releng/releases/2026.08.01/> (kernel
  7.1.5, package snapshot dated after archinstall 4.4's release; no newer
  archinstall tag exists to have shipped instead).
- PyPI: `archinstall` project page lists 4.4 as latest. Source:
  <https://pypi.org/project/archinstall/>

`NOTES.md`'s claim ("ships archinstall 4.4") is still accurate two months
later — nothing to update there.

## How verification was done

All field-level verdicts below are checked against the actual **source
code** of the `archlinux/archinstall` GitHub repo at git tag `4.4`
(pinned, not `master`) — the dataclasses/enums that define what
`--config`/`--creds` JSON is parsed into and serialized from — not just
prose docs, since (see note below) the prose docs and the `schema.json`
example lag behind the code on several points.

Key files read at tag `4.4`:
- `archinstall/lib/args.py` — `ArchConfig`, `ArchConfigType`,
  `ArchConfigHandler._parse_config`/`_cleanup_config` (top-level config
  assembly, creds merge, `null`-stripping)
- `archinstall/lib/models/bootloader.py` — `Bootloader`,
  `BootloaderConfiguration`
- `archinstall/lib/models/device.py` — `DiskLayoutConfiguration.parse_arg`,
  `EncryptionType`, `DiskEncryption`, `PartitionType`, `FilesystemType`,
  `ModificationStatus`, `PartitionFlag`
- `archinstall/lib/models/mirrors.py` — `MirrorConfiguration`
- `archinstall/lib/models/profile.py` — `ProfileConfiguration.parse_arg`
  (gfx_driver validation, including the removed-value error message)
- `archinstall/lib/hardware.py` — `GfxDriver` enum (canonical driver
  strings)
- `archinstall/lib/models/authentication.py` — `AuthenticationConfiguration`
- `archinstall/lib/models/application.py` — `ZramConfiguration` (`swap`)
- `archinstall/lib/models/pacman.py` — `PacmanConfiguration`
- `archinstall/lib/version.py` — `get_version()`
- `examples/config-sample.json`, `examples/creds-sample.json` (repo
  examples, tag `4.4`)
- `docs/installing/guided.rst` and
  `docs/cli_parameters/config/config_options.csv` (the readthedocs
  source, tag `4.4`) — for the `--creds` schema table and cross-checking
  prose docs against code
- Root `schema.json` (legacy JSON-Schema-ish file left in the repo)

Permalinks below use the `4.4` tag so they stay pinned even if `master`
moves on.

## Field-by-field verdict

### `disk_config.device_modifications[].partitions[]`

**MATCHES CURRENT SCHEMA.**

`DiskLayoutConfiguration.parse_arg` (archinstall/lib/models/device.py,
tag 4.4) directly indexes `partition['status']`, `partition['start']`,
`partition['size']`, `partition['mount_options']`, `partition['mountpoint']`,
`partition['dev_path']`, `partition['type']`, `partition['obj_id']`, and
`.get()`s `partition['flags']`/`partition['btrfs']`/`partition['fs_type']`
— exactly the key set the tracked file's two partitions use. The enum
values used (`"fat32"`, `"btrfs"` for `fs_type`; `"primary"` for `type`;
`"create"` for `status`; `"boot"`/`"esp"` for `flags`) all match
`FilesystemType`, `PartitionType`, `ModificationStatus`, and
`PartitionFlag` respectively (all lowercase `StrEnum` `auto()` values, or
matched case-insensitively via `PartitionFlag.from_string`).

Citation:
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/device.py>
(`DiskLayoutConfiguration.parse_arg`, `~L115-200`; enum classes
`PartitionType` `~L756`, `PartitionFlag` `~L783`, `FilesystemType` `~L818`,
`ModificationStatus` `~L858`).

### `disk_config.disk_encryption`

**MATCHES CURRENT SCHEMA** — and specifically matches the *current,
non-deprecated* location for this data.

`EncryptionType` is a `StrEnum` with `LUKS = auto()` → value `"luks"`,
confirming `"encryption_type": "luks"`. The `_DiskEncryptionSerialization`
TypedDict is `{encryption_type: str, partitions: list[str], lvm_volumes:
list[str], hsm_device?: ..., iter_time?: ...}` — `partitions` here is a
list of **partition `obj_id` UUID strings** (matching the tracked file's
`disk_encryption.partitions: ["a1b2c3d4-..."]`, which is the same UUID as
the btrfs root partition's `obj_id`), not device paths. `lvm_volumes: []`
matches too.

Important nuance found in the code: `args.py` (`ArchConfig.from_config`,
`~L269-286`) explicitly labels a **top-level** `disk_encryption` key
(sibling of `disk_config`, not nested inside it) as `# DEPRECATED /
backwards compatibility`. The tracked file correctly nests
`disk_encryption` *inside* `disk_config` (`disk_config.disk_encryption`),
which is parsed via the primary, non-deprecated path in
`DiskLayoutConfiguration.parse_arg` (`~L230`:
`config.disk_encryption = DiskEncryption.parse_arg(config, enc_config, enc_password)`).
So the repo is already on the modern shape — good, nothing to change.

Citation: <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/device.py>
(`EncryptionType` `~L1439`, `_DiskEncryptionSerialization` `~L1465`,
`DiskEncryption` `~L1474`) and
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/args.py>
(`~L269-286`, the `# DEPRECATED` comment for top-level `disk_encryption`).

### `bootloader_config` keys

**MATCHES CURRENT SCHEMA** (plus one new, optional field not present in
the tracked file, which is fine).

`BootloaderConfiguration` (dataclass) fields: `bootloader: Bootloader`,
`uki: bool = False`, `removable: bool = True`, and — new since older
versions — `plymouth: PlymouthTheme | None = None`. Its `json()` only
emits `plymouth` when set. The tracked file's `{bootloader: "Grub", uki:
false, removable: false}` is a fully valid, complete
`BootloaderConfiguration` with `plymouth` simply left at its default
(omitted). `Bootloader` enum values: `'No bootloader'`, `'Systemd-boot'`,
`'Grub'`, `'Efistub'`, `'Limine'`, `'Refind'` — `"Grub"` is valid and
unchanged.

Citation: <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/bootloader.py>
(`Bootloader` enum, `BootloaderConfiguration` dataclass and `.json()`).

Note: `docs/cli_parameters/config/config_options.csv` (readthedocs
source) still lists only lowercase `grub`/`limine` bootloader values and
doesn't mention `plymouth` at all — the prose docs lag the code here.
Case doesn't matter in practice: `Bootloader.from_arg` calls
`.capitalize()` on the input before matching, so `"grub"` and `"Grub"`
both resolve.

### `profile_config.gfx_driver`

**MATCHES CURRENT SCHEMA** — and this is the one area that specifically
would have broken had the tracked file used the deprecated value.

The canonical `GfxDriver` enum (archinstall/lib/hardware.py) is:
`'All open-source'`, `'AMD / ATI (open-source)'`,
`'Intel (open-source)'`,
`'Nvidia (open kernel module for newer GPUs, Turing+)'`,
`'Nvidia (open-source nouveau driver)'`, `'VirtualBox (open-source)'`.
The tracked file's value,
`"Nvidia (open kernel module for newer GPUs, Turing+)"`, matches this
enum's value **exactly, character for character**.

Confirmed deprecation: `ProfileConfiguration.parse_arg`
(archinstall/lib/models/profile.py) explicitly checks for the *old*
value and rejects it:

```python
if gfx_driver == 'Nvidia (proprietary)':
    raise ValueError(
        'The Nvidia proprietary driver (nvidia-dkms) has been removed from the Arch repos. '
        'Please use "Nvidia (open kernel module for newer GPUs, Turing+)" instead.'
    )
```

So `"Nvidia (proprietary)"` — an option that still shows up in the stale
root `schema.json` in the repo — is now a hard error, and the exact
string the error message recommends is the one already used in
`user_configuration.json`. No action needed; this is exactly the kind of
rename this research was meant to catch, and it turns out the tracked
file already has the post-rename value.

Citation:
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/hardware.py>
(`GfxDriver` enum) and
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/profile.py>
(`ProfileConfiguration.parse_arg`, the `'Nvidia (proprietary)'` check).

### `mirror_config` shape

**MATCHES CURRENT SCHEMA.**

`MirrorConfiguration` dataclass fields: `mirror_regions:
list[MirrorRegion]`, `custom_servers: list[CustomServer]`,
`optional_repositories: list[Repository]`, `custom_repositories:
list[CustomRepository]` — its `.json()` serializes exactly the four keys
the tracked file uses: `mirror_regions`, `custom_servers`,
`optional_repositories`, `custom_repositories`.

`MirrorConfiguration.parse_args` also accepts a legacy `custom_mirrors`
key as a backwards-compatible alias for `custom_repositories` — this
confirms `custom_mirrors` (still shown in the stale
`config_options.csv` docs) is the *old* name and `custom_repositories`
(what the tracked file uses) is current.

Citation: <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/mirrors.py>
(`MirrorConfiguration` dataclass, `.json()`, and `.parse_args()`'s
`custom_mirrors` backward-compat branch).

### `swap` object

**MATCHES CURRENT SCHEMA.**

`ZramConfiguration` (archinstall/lib/models/application.py): `enabled:
bool`, `algorithm: ZramAlgorithm = ZramAlgorithm.ZSTD`. Its
`.json()` emits exactly `{"enabled": ..., "algorithm": ...}`, matching
the tracked file's `{"enabled": true, "algorithm": "zstd"}` verbatim.
`parse_arg` also accepts a plain boolean (`swap: true`) as shorthand, but
the object form used in the repo is the fully-specified, still-current
form.

Citation:
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/application.py>
(`ZramConfiguration` class, `~L172-190`).

### `auth_config`

**MATCHES CURRENT SCHEMA** (explicit `null` is harmless/equivalent to
omitted).

`ArchConfigHandler._cleanup_config` (args.py) recursively strips any key
whose value is `None` out of the merged config dict *before* it's handed
to `ArchConfig.from_config`. So `"auth_config": null` in the tracked file
is stripped during parsing and has exactly the same effect as the key
being absent — which is also exactly what `examples/config-sample.json`
does (it omits `auth_config` entirely). `auth_config`
(`AuthenticationConfiguration`) is only used today to carry `u2f_config`
in the *config* file; `root_enc_password` and `users` (the credentials
normally associated with "auth") are read from **separate top-level
keys**, sourced from the `--creds` file, not from an `auth_config` object
at all.

Citation: <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/args.py>
(`_cleanup_config`, ~L780-790, drops `None` values; `AUTH_CONFIG` handling
`~L321-322`) and
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/models/authentication.py>
(`AuthenticationConfiguration`, only serializes `u2f_config`).

### Top-level `"version"` field

**MATCHES CURRENT SCHEMA, but is informational only — not actually
read/validated on input.**

`ArchConfig.from_config()` never reads `args_config.get('version', ...)`
at all. Instead, `ArchConfigHandler.__init__` unconditionally overwrites
whatever came in with `self._config.version = get_version()`
immediately after parsing (`archinstall/lib/args.py`, ~L478-480), and
`get_version()` (`archinstall/lib/version.py`) just returns
`importlib.metadata.version('archinstall')` — i.e. whatever archinstall
package is actually installed and running. So the `"version"` key in an
input `--config` JSON is pure metadata with **zero effect on parsing or
validation** — there is no version-compatibility gate on it. (The
`--skip-version-check` flag / `check_version_upgrade()` in
`archinstall/lib/main.py` is a *different* check: it pings PyPI to see if
a newer archinstall package is available, unrelated to the config file's
`version` field.)

Practically: `"version": "4.4"` in the tracked file happens to be
literally correct (that's what's installed on the target ISO today), but
even if it weren't, it would not break anything — it would just get
silently overwritten with whatever `archinstall --version` actually is
at install time. Nothing to change, and no future-proofing needed on
this field specifically.

Citation: <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/args.py>
(`ArchConfig.from_config`, no `version` key read; `ArchConfigHandler.__init__`
~L478-480) and
<https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/version.py>.

## `--creds` (`user_credentials.json`) schema

**A stable, citable, primary-source schema does exist** — in the official
readthedocs docs, whose source lives in the archinstall repo itself:

`docs/installing/guided.rst`, section "Options for `--creds`"
(archinstall repo, tag 4.4):

```json
{
    "root_enc_password" : "SecretSanta2022"
}
```

| Key | Type | Description | Required |
|---|---|---|---|
| `encryption_password`* | `str` | LUKS disk encryption password (plaintext; not encrypted if omitted) | No |
| `root_enc_password` | `str` | Root account password | No |
| `users` | list of `{"username": str, "enc_password": str, "sudo": bool}` | Regular user credentials | "Maybe" — required (min. 1 sudo user) unless `root_enc_password` is set |

\* The rendered docs table shows this key as `!encryption-password`
(with what looks like a stray RST escape character and a hyphen); the
actual source code disagrees and uses an **underscore**:
`archinstall/lib/args.py` defines `ArchConfigType.ENCRYPTION_PASSWORD =
'encryption_password'` and reads it via
`args_config.get('encryption_password', '')` at the top level of the
merged config (i.e. also settable from the `--creds` file, since creds
and config get merged into one dict before parsing). Treat
`encryption_password` (underscore) as authoritative — it's the literal
string used in the parser, not the docs table's rendering.

`examples/creds-sample.json` in the same repo tag corroborates the
`users`/`root_enc_password` shape (no `encryption_password` example
given, but the key is confirmed live in `args.py`).

This is enough of a stable, first-party contract to cite going forward
for a patcher script that also needs to set the LUKS password
(`encryption_password`) and/or user password (`users[].enc_password`) —
just note it's spread across the docs page (for `users`/
`root_enc_password`) and the source code (for the exact
`encryption_password` key name, since the docs table's rendering of that
one row is unreliable).

Citation: <https://github.com/archlinux/archinstall/blob/4.4/docs/installing/guided.rst>
(section "Options for `--creds`", ~L255-297, rendered at
<https://archinstall.readthedocs.io/installing/guided.html#options-for-creds>)
and <https://github.com/archlinux/archinstall/blob/4.4/archinstall/lib/args.py>
(`ArchConfigType.ENCRYPTION_PASSWORD`, `~L89` and its usage `~L270,190`)
and <https://github.com/archlinux/archinstall/blob/4.4/examples/creds-sample.json>.

## A caution for future patch-script work: docs and root `schema.json` are stale

Two things in the archinstall repo itself are **not** reliable as of
4.4, and should not be used as the source of truth for a future patcher
script without cross-checking the actual Python source:

1. **Root `schema.json`** (`archinstall/schema.json` at the repo root) —
   describes the old, pre-4.0 *flat* config shape (top-level
   `bootloader`, `harddrives`, `mirror-region`, nested `profile.gfx_driver`
   including the now-rejected `"Nvidia (proprietary)"`). It does not
   reflect `bootloader_config`, `disk_config`, `mirror_config`, etc. at
   all. Do not use it to validate/generate the current nested config
   shape.
2. **`examples/config-sample.json`** (tag 4.4) — still has `"version":
   "2.8.6"` baked in from whenever it was last hand-edited, and lacks
   `disk_encryption`/`auth_config` examples (it's an unencrypted,
   no-auth-config sample). Useful for the general shape (and it does
   confirm current `mirror_config`/`bootloader_config`/`swap` field
   names), but don't trust its `version` value or treat it as
   exhaustive.
3. **`docs/cli_parameters/config/config_options.csv`** (readthedocs
   source) — still documents the deprecated top-level `disk_encryption`
   key (not the current `disk_config.disk_encryption` nesting), the
   deprecated `custom_mirrors` mirror key, and a boolean-only `swap`
   value, and doesn't mention `gfx_driver`, `auth_config`, or
   `app_config` at all. The Python source (`archinstall/lib/args.py` and
   `archinstall/lib/models/*.py`) is the actual ground truth and is what
   every verdict above was checked against.

## Summary table

| Area | Verdict |
|---|---|
| `disk_config.device_modifications[].partitions[]` | MATCHES CURRENT SCHEMA |
| `disk_config.disk_encryption` (nested shape) | MATCHES CURRENT SCHEMA (also: confirmed non-deprecated location) |
| `bootloader_config` keys | MATCHES CURRENT SCHEMA (optional `plymouth` field exists but isn't required) |
| `profile_config.gfx_driver` value | MATCHES CURRENT SCHEMA (old `"Nvidia (proprietary)"` value now hard-errors; tracked file already uses the correct replacement) |
| `mirror_config` shape | MATCHES CURRENT SCHEMA |
| `swap` object | MATCHES CURRENT SCHEMA |
| `auth_config: null` | MATCHES CURRENT SCHEMA (stripped as a no-op by `_cleanup_config`) |
| top-level `"version"` | MATCHES CURRENT SCHEMA, but informational-only (not read on input, always overwritten with the running package's version) |
| `--creds` schema | Stable public schema exists (readthedocs `guided.rst` + source code); one docs-table rendering glitch noted for `encryption_password` |

**Recommendation:** the tracked `user_configuration.json` needs no schema
migration right now. A future device/hostname/gfx_driver patcher script
can safely target this exact file shape. Revisit this file after any
future archinstall major/minor bump (watch specifically for further
`GfxDriver` enum renames — it's clearly a value archinstall is willing to
rename/remove — and for whether `disk_encryption` ever gets fully removed
from its still-documented-as-deprecated top-level form, which is
irrelevant here since the repo already uses the nested form).
