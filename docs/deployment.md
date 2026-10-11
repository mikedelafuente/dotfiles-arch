# Blue/green DFA deployment

`~/.local/share/workstation/config` points to one installed copy: `blue` or `green`.
A fresh install starts with `blue`. Update the inactive folder, validate it, then
switch `config`. The formerly active folder is the previous backup. No generation
history, per-file manifests, content hashes, baselines or automatic merging.
Installed tools remain usable when source checkouts move or disappear.

## Storage

Paths are relative to `~/.local/share/workstation`, using `USER_HOME_DIR`.

| Path | Purpose |
| --- | --- |
| `blue/`, `green/` | Complete installed source closure, registered resources and generated instructions |
| `config` | Activation symlink to `blue` or `green` |
| `previous` | Symlink to the previous installed copy, absent on first install |
| `blue/.dfa/sources.json`, `green/.dfa/sources.json` | Source paths, readable IDs, sanitized origins, ordinary Git commit IDs |
| `blue/.dfa/links.json`, `green/.dfa/links.json` | Managed home link destinations and their relative installed paths |
| `staging/` | Temporary incoming copy and retired inactive copy during activation; removed afterward |
| `lock`, `transaction.json` | Exclusive deployment lock and interrupted-activation recovery |

The two small records locate editable sources and protect home link ownership.
They contain no file fingerprints or merge state. Extra source IDs use readable
folder names, with numeric suffixes for collisions, and stay stable across updates
and explicit rebinds. `.dfa/` is reserved in the installed root.

Root invocations drop to `SUDO_USER`. State is private (root 0700, records 0600).
Executable permissions are retained. Source symlinks must resolve inside the
copied source closure; external, broken or excluded targets block deployment.

## Edit and update

Run `dfa-deploy source` before shared edits. For an extra source, use
`dfa-deploy source --source-id ID`; `dfa-deploy status` lists IDs and edit paths.
Never treat installed copies as editable source repositories.

- `dfa-deploy deploy`: copy primary checkout working files, including staged,
  unstaged and non-ignored additions/deletions. No fetch or commit.
- `dfa-deploy deploy --committed`: use committed HEAD instead.
- `dfa-deploy update`: require a clean primary checkout, pull with `--ff-only`,
  then copy committed files. Extra Git sources use committed HEAD; non-Git roots
  use supplied files. Refresh/acquisition remains explicit.
- `--dry-run`: report without writes or acquisition.

Deploy replaces installed-only edits and applies source deletions. Keep local
preferences and application-owned state outside managed files. `override` and
`capture` are removed; copy a selected improvement to its source yourself for
review before deployment.

The copy excludes `.git`, credentials/authentication files, `.env*`, bootstrap
secrets, `node_modules`, Python caches and Pi models-store runtime state.
Machine-local Git identity stays in real `~/.gitconfig`; shared Git settings use
`~/.config/git/config`. Existing application-owned paths remain unchanged.
A resolving legacy Pi models-store link is detached into its machine-local file;
a broken link blocks deployment. This state is never restored from backups.

## Validation, ownership and recovery

Stage the complete copy before changing activation. Validate JSON/JSONC, TOML,
Python and Bash syntax without running source scripts. Syntax checks do not prove
application schemas or desktop/hardware compatibility. Missing registered sources,
protected skill collisions, ownership conflicts or validation failures leave the
active installation working. Registered extras apply first; primary rules win by
basename. A losing skill source must explicitly permit duplicate replacement.
Pi native-package and installed-copy resource loading remain mutually exclusive.

Only absent or managed home targets may be linked. Preserve unrelated real files,
foreign symlinks and redirected parents. Legacy directory links must not hide
unknown descendants. Installed files inside blue/green are disposable; put
unmanaged files outside those folders.

Activation journals the old pointer and home links before switching. Recovery
restores incomplete activations; after a committed switch it finishes cleanup.
`dfa-deploy recover` uses the same exclusive lock and preserves foreign link or
Claude-instruction edits encountered during recovery. User-written Claude
instructions remain intact; deployment adds only its owned import.

`dfa-deploy rollback` switches to the previous copy and restores its managed links.
It does not reverse packages, services, saved settings, schema stamps, source Git
work or source registration. Installed edits may be discarded by rollback.
The two folders are reused: runtime helpers resolve subsequent dependencies through
stable `config`, rather than relying on indefinite retention of an old path.

## Source moves and ownership handoffs

### Repository rename

The GitHub repository is now `mikedelafuente/dotfiles-linux`. Existing checkout
folders may retain their old name. Keep a recorded origin unchanged until an
explicit deployment is intended: GitHub redirects the old repository URL, while
DFA compares the local origin against installed provenance.

To adopt the new origin and deploy after reviewing or committing source changes:

```bash
cd "$(dfa-deploy source)"
git remote set-url origin git@github.com:mikedelafuente/dotfiles-linux.git
dfa-deploy rebind "$PWD" --accept-origin-change
```

Rebind deploys source files; it is not a metadata-only operation. The rename
preserves `dfa-*` commands, `DOTFILES_ARCH`, `dotfiles-arch-lib.sh`, existing
configuration/data paths and ownership markers.

### Source rebinding

Restore an unavailable checkout or run `dfa-deploy rebind /actual/checkout`.
Rebind verifies Git ancestry and origin; a renamed origin requires
`--accept-origin-change`. For extra roots, add `--source-id ID`. Never discover a
replacement checkout by basename. Configured sources live in
`~/.config/dotfiles-arch/sync-sources` and are manually registered; deployment never
acquires an unregistered source.

`.dfa-source-handoffs.json` declares primary resource moves to registered standard
sources. Removed source-backed files must have exact replacements in the named
source. Missing registration or replacement blocks deployment. Replacement source
bytes win; installed edits are retained only in the immediately previous backup.

## Migration and maintenance

Schema v6 uses the existing migration runner and stamp. `v5-to-v6-migration.sh`
converts legacy generations automatically and is safe to retry. Preserve the active
legacy tree as `blue`, install source bytes into `green`, then activate `green`.
Only after successful activation remove managed old generations and the retired
override store. Existing installed edits/override effects survive in the first
backup but are not reapplied on later deploys. Migration reads legacy opaque IDs
only to locate and translate existing data; no hashes are computed or retained in
new deployment records. Failure preserves the old usable installation and does not
advance the schema stamp. Migration of an already blue/green layout is a no-op.
The backup keeps a blue/green-compatible deployment controller so maintenance
works after rollback. Its original controller bytes are retained as inert backup
data in `.dfa/legacy-deployment.py`; other installed files keep their original bytes.
Recover an outstanding v5 activation with the installed v5 manager before migration.

Daily ordering: refresh repositories → acquire/deploy the primary source → at most
one restart into updated helpers → migrations → native/app updates → resource sync.
Source/deployment/migration failures block dependent work. Weekly calls daily first.
Local deploy and full sync do not acquire source updates. All resource sync entry
points converge on deployment; identical copies use direct byte/mode comparison
and do not switch folders. Package owners and cooldowns keep their existing rules.

## Verification

Run `python3 tests/test_deployment.py`, `python3 tests/test_source_handoff.py` and
`python3 tests/test_generic_consumer.py` with temporary supplied homes/sources.
These cover copying, source replacement, registered resources, ownership,
backup/rollback, migration, interrupted activation, concurrency and maintenance
ordering. Use `bash scripts/check.sh` for shipped shell syntax/shellcheck.
Implementation and fixture checks do not authorize live workstation deployment.
