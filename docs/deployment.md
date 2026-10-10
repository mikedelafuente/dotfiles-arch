# Stable DFA deployment

DFA installs managed copies at `~/.local/share/workstation/config`, a stable symlink to a
complete retained generation. Home configuration links point through this path.
A checkout can move or disappear without breaking installed shells, editors,
hooks, launchers or maintenance dependencies. Shared source acquisition and edits
still require the explicitly recorded checkout. Clone a public source using HTTPS;
deploy/capture/rebind require no GitHub login. Source updates use Git's configured
transport and credential helpers; installation never requires `gh auth`.

## Storage and provenance

All paths below are relative to `~/.local/share/workstation` (using `USER_HOME_DIR`).

| Path | Contract |
| --- | --- |
| `config` | Atomic activation symlink to `generations/<id>/tree` |
| `generations/<id>/tree` | Installed tracked source closure, extra sources, generated instructions |
| `generations/<id>/baseline` | Incoming **source** bytes/modes, independent of locally merged copies |
| `generations/<id>/manifest.json` | Checkout path, sanitized URL, commit, origins, source/baseline/deployed identities and home link ownership |
| `generations/<id>/rollback.json` | Previous activation, original link targets and pre-activation schema/import state |
| `config/DEPLOYMENT-README.md` | Installed-copy guidance; generation also has a `README.md` beside `tree` |
| `staging/<id>` | Unactivated incoming/candidate/baseline copies; failures remain here |
| `staging/<id>/pending/<artifact>` | Literal B/L/I inputs when present, plus reason and resolution steps |
| `overrides/<artifact>` | Persistent explicit local override; overrides have priority over merges |
| `lock`, `transaction.json` | Exclusive deployment lock and interrupted-activation recovery journal |

Staging IDs derive from the incoming/baseline/live/override/provenance state; repeated
identical conflicts report the same retained evidence. Generation storage adds an
unused numeric suffix when necessary to preserve an existing backup. Merge bytes
and diagnostics depend only on supplied input/state. URLs omit user info, queries and fragments. No `.git`
metadata, authentication files, `.env*`, Pi auth or models-store, bootstrap secrets,
`node_modules`, or Python caches are copied. Machine-local Git identity stays in
`~/.gitconfig`; saved preferences and application-owned state keep their existing
paths. A proven resolving legacy Pi models-store link is detached into its machine-local
file after activation; it is excluded from backups and stays local across rollback.
Root invocations drop to `SUDO_USER` before creating generations. State is
private (root directory 0700, JSON state 0600); managed file executable modes are
retained. Backups are retained indefinitely; this version has no pruning command.

Example manifest fragment (per-source details also cover configured extra roots):

```json
{
  "sources": [{"id": "primary", "path": "/home/example/src/workstation",
    "url": "https://github.com/example/workstation", "commit": "<commit>",
    "type": "standard", "overwritable": false}],
  "artifacts": {"home/.bashrc": {"source": "primary", "relative": "home/.bashrc",
    "origin": "/home/example/src/workstation/home/.bashrc",
    "baseline": {"kind": "file", "sha256": "<incoming hash>", "mode": 420},
    "deployed": {"kind": "file", "sha256": "<merged hash>", "mode": 420}}}
}
```

## Deterministic merge and validation policy

B is the last successful incoming source, L is the current installed copy, and I
is incoming source content. `dfa-deploy deploy` snapshots the primary checkout's
working files, including staged/unstaged edits, deletions and non-ignored new files,
without committing or fetching. Source sync, `dfa-sync-dotfiles` and standalone
setup commands use this path so local changes can be tested immediately.
`dfa-deploy update` still requires a clean checkout, pulls with `--ff-only`, then
stages committed HEAD. `dfa-deploy deploy --committed` deploys HEAD without fetching;
the initial v5 migration uses this to preserve its existing legacy-file safeguards.
Extra Git sources continue to use committed HEAD.
Working snapshots retain HEAD provenance plus a working-status digest and artifact
hashes; path/content changes during staging block activation. Capture leaves edits
uncommitted for review. Non-Git extra roots use their
explicitly supplied content as I. A successful generation advances B to I, never to the merged
L. The transaction boundary is the **whole generation**: any conflict or validation
failure blocks every artifact, link and provenance advancement.

Unchanged/local-only/source-only edits follow three-way comparison. Strict JSON
uses recursive object-key reconciliation; missing keys differ from null. Deletion
wins against unchanged content; deletion versus edit and incompatible type edits
conflict. Local-only keys survive. Arrays are atomic. Duplicate keys and nonfinite
numbers fail parsing. JSONC is supported for `.jsonc` and Zed's comment-capable
settings/keymap: validate syntax after removing comments/trailing commas, verify
semantic conflicts using the same object/array policy, then merge original text
with `git merge-file`. Comments and array order are retained, never rewritten into
strict JSON. Other text, including TOML, uses `git merge-file`; ambiguous hunks
remain pending. TOML, Python and Bash candidates receive syntax checks. These checks
do not validate application schemas or run user code.

New absent artifacts can be copied directly. Existing binary changes, artifact
kind changes, missing/altered baselines and unverifiable initial live content are
pending. A proven resolving legacy checkout link can use that source's recorded
Git HEAD as its initial baseline. Unrelated real files and links are ownership
conflicts even when their content happens to match. Broken legacy links retain
their original evidence and require restoring the source. Initial generated rule
copies with no trusted baseline require an explicit override, rather than assuming
that their local content can be discarded. After such a pending attempt, override
accepts keys from the retained initial inventory.

Use `dfa-deploy status` to locate provenance and retained pending runs. A conflict
installs no markers and leaves the live file byte-for-byte unchanged. Review the
reported B/L/I inputs, produce a regular resolution file, then run:

```bash
dfa-deploy override home/.bashrc /path/to/resolved-bashrc
dfa-deploy deploy
```

Omitting the file removes an override; the next deployment reconciles live changes
against the retained source baseline. Overrides persist independently of source
moves and rollback. An override for a removed upstream artifact blocks deployment.
Unmanifested files added inside managed installed folders also block deployment;
move them outside those folders explicitly so the next generation cannot hide them.
The same guard applies to rollback and recovery. Initial legacy directory links also
preflight every descendant; unknown files block migration rather than disappearing
behind a new skill/extension link.

## Source operations and edit destinations

`dfa-deploy source` verifies the recorded path, repository URL and commit ancestry,
then prints the actual shared edit destination. Missing/stale provenance stops
source edits with a diagnostic; an installed folder is never substituted as source.
The per-file manifest identifies extra-source edit destinations. Shared edits made
in that checkout are reviewable Git changes. Edit installed copies only for intended
local differences, or record a persistent override. Select one regular source-backed
artifact with `dfa-deploy capture <artifact>` to copy a local improvement into its
actual source. Capture refuses an independently dirty destination and leaves other
dirty files alone. It rejects literal JSON/TOML credential values (environment-key
references are allowed); known authentication files are excluded from management.
It performs no commit, push or network write.

After moving/replacing a clone, run `dfa-deploy rebind /actual/checkout`. The clone
must contain the recorded source commit. A repository rename additionally requires
`--accept-origin-change`; this acknowledges the inspected new origin explicitly.
For a configured extra source, use `rebind /actual/source --source-id <id>` from
`status`; this updates its registry path and preserves the installed artifact IDs.
Rebind stages a normal generation so even content-identical moves refresh provenance
and generated harness guidance, with rollback retaining the old manifest. An
unavailable configured extra source is pending until restored or explicitly removed
with `dfa-sync-sources`. No basename-based clone selection occurs.

## Activation, interruption and rollback

### Registered source ownership handoffs

The primary checkout can declare data ownership moves in
`.dfa-source-handoffs.json`:

```json
{"version": 1, "moves": [
  {"from": "skills", "to": "skills", "source": "https://github.com/mikedelafuente/skills"}
]}
```

This declaration neither acquires nor registers a source. Each disappeared primary
artifact must have an exact relative replacement in one manually registered
standard source with the declared origin. Missing registration or replacement
blocks deployment. The move reuses the original installed B/L inputs against the
replacement I, then records the replacement origin and baseline in the new
manifest. Local edits merge normally; competing edits block the entire generation.
An already deployed replacement must have its baseline intact and no local edit
or override of its own, otherwise both copies need explicit reconciliation.

The manifest's `override_artifact` retains the original persistent override-store
key. Use the **new** manifest artifact key with `dfa-deploy override` and `capture`;
override edits/removal still address that original key, including after rollback.
Retained generations keep the previous ownership and home links for rollback.
Never remove a replacement snapshot before the old source has contracted and the
human has verified the handoff. A missing registered source blocks further
deployment while the installed generation stays usable.

Deployment takes an exclusive nonblocking lock, stages and validates, rechecks source
and live bytes/modes and home link ownership, then journals the activation before
switching `config`. Executables resolve their real generation and use libraries
from that same generation. Old generations remain available to running processes.
File additions/removals require home link changes after the atomic pointer switch;
they are journaled and recoverable. An activation failure restores original links
and state. `dfa-deploy recover` rolls an interrupted activation back; unrelated
link drift requires explicit inspection instead of overwriting it.

`dfa-deploy rollback` restores previous content, home links, baseline/provenance,
schema stamp and the managed Claude import change. It refuses post-activation live
edits or foreign link drift; capture/copy those edits before retrying. Initial
migration rollback returns original checkout links, so the original checkout must
still resolve. The retained generation preserves installed content as a backup.
Rollback does not uninstall packages, reverse GNOME/service mutations, reset saved
preferences, or alter source Git work. Dry-run performs no writes or acquisition.

## Migration and daily ordering

The existing schema tracker gains `v4-to-v5-migration.sh`; no parallel tracker exists.
An unstamped machine without a deployment is v4 even if all checkout links still
resolve. Older dangling-name landmarks still take priority. Fresh/stamped-v4 machines
stage v5 before replacement; an existing deployment needs only interrupted stamping
or normal no-op replay. Failure never advances the schema stamp. `--dry-run` retains
all runner behavior. `--rerun-all` retains the older migrations' existing semantics
(including the historical Zed setup); it is not a validation command to run against
a workstation. Normal v5 migration has no package/service operations.

Bootstrap deploys before setup scripts can link checkout paths; standalone source
setup entrypoints also deploy before executing their installed counterpart. Link,
post-link, individual rules/skills/extensions sync and daily all converge on the
same deployment boundary. Existing machine-local Git conversion is retained.

Daily ordering is: refresh repositories (clean trees only) → explicitly update the
recorded primary source → stage/merge → syntax validation → activation → at most one
restart into the complete new generation → existing migrations → native/app updates
and configured dependent steps. Source unavailability, dirty primary source,
conflict or migration failure blocks subsequent dependent mutation. Weekly maintenance stops when daily fails. Package owners,
cooldowns and update success-stamp rules stay in their existing implementations.
Configured extra sources are refreshed by the repository refresh step when under
its configured search root; outside that root their acquisition remains explicit,
and deployment still verifies their presence and records their content origins.

## Static dependency inventory

The closure includes the complete source tree, minus explicit secret/state/cache
exclusions. Local deployment reads tracked working files and non-ignored additions;
ignored tracked files remain included. Acquisition and extra Git sources use raw
committed blobs, which preserve files even when
export-ignore/export-subst attributes would change an archive. This deliberately includes documentation
and skill support resources; trying to derive imports for Bash/Lua/TypeScript would
be less reliable. Standard extra roots have the same closure; non-Git extra roots
copy only their configured supplied tree, rejecting broken/external links.

| Managed consumer | Previous dependency | Installed dependency / remaining source operation |
| --- | --- | --- |
| `.bashrc`, `.profile`, `.inputrc`, `.tmux.conf`, welcome/cheatsheet/gitignore | `home/*` links | `config/home/*`; external programs remain their package owners |
| `~/.packages.md` | `home/.packages.md → ../PACKAGES.md` | Internal relative link resolves to installed `config/PACKAGES.md` |
| Git, Kitty, tmux, Neovim/Lua, Zed, fontconfig, bat, shell/theme configs | `config/**` | Stable home links to installed `config/config/**` |
| `dev`, `zed-agent-init`, `nvim-reveal-edit` and GNOME window helpers | Sibling runtime library and script path lookup | Real-generation sibling library; installed `scripts/*` for editor/runtime checks |
| All `home/.local/bin/dfa-*` wrappers | Checkout resolver, sourced `dotheader.sh` / `fn-lib.sh` | Real-generation root; all `scripts/*`, Python helpers, migrations, NinjaOne assets retained |
| `dfa-update-system`, npm/app/weekly/NinjaOne maintenance | Backend scripts and owned package/app state | Installed backend dependencies; native/vendor acquisition keeps existing owners |
| `dfa-check-dotfiles` | Source lint tree | Installed complete scripts/migrations/helper tree |
| `dfa-migrate`, link/post-link/bootstrap/sync | Repository migrations and unconditional linking | Installed migrations; source entrypoints stage before linking/setup |
| Pi models/settings/agents/extensions | `pi/**`, extra extensions roots; imported TS modules | Installed `pi/**`/extra closure; auth/models-store remain machine-local |
| Claude/Cursor/Codex/Pi skill folders | Recursive source skill parent links and relative support paths | Discovered installed parents and support closure; protected collision policy retained |
| Cursor rules, Claude imports, Codex/Pi/OpenCode global guidance | Raw sources and generated rules-build artifacts | Installed generated normalized rules and direct installed-copy/source instructions |
| `dfa-sync-sources` | Source paths in registration | Machine-local source registry retained; deploy owns activation/pruning of manifested targets |
| Source update, individual source sync, capture, source lookup, rebind | Git checkout and provenance | **Explicit source-only operations**; unavailable source is pending, runtime stays installed |
| `dfa-repos`, `dfa-update-repos`, editor project Git operations | User project directories | Intentionally source/project operations, independent of DFA runtime provenance |
| Cloud-agent config installer | Supplied source and cloud target | Separate explicit source installer; not a workstation runtime dependency |

Old rule-build copies and unrelated links/files are preserved. Generated combined
instructions replace active rule imports where DFA owns them; unmanaged harness
instructions remain user-owned. No current workstation migration, deployment or
rollback is executed as part of implementing this change.

## Evidence and limits

Run `python3 tests/test_deployment.py`, the existing `tests/test_*.py` decision checks,
and `bash scripts/check.sh`. Fixtures use supplied repositories and temporary homes,
without network, sudo, package/service/GNOME/driver actions or OS/VM provisioning.
They test merge results/pending preservation, ownership, provenance, migration
ordering, generation closure and source disappearance. Static/fixture proof does
not establish real workstation migration/rollback, desktop/app parity, actual
credential/update transport, hardware, schema-specific app acceptance or installation.

OpenCode global guidance uses its documented `~/.config/opencode/AGENTS.md` path
([official rules documentation](https://opencode.ai/docs/rules/)).

Recovery covers process interruption through the retained journal; filesystem/power-loss
durability is not established by temporary-state fixtures.
