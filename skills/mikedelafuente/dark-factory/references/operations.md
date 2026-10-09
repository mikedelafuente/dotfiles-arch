# Local control API, schema version 1

Use the resolved installed `dark-factory/scripts/control.py` path. All state is
local private JSON; no command calls a runner/tracker or creates a schedule.
These guards consume adapter-verified facts, not self-authenticating assertions.

| CLI | Result |
|---|---|
| `init STORE BUNDLE.json` | Validate envelope and pinned accepted records; create immutable bundle/private state, awaiting idea approval; refuses an existing lineage |
| `apply STORE EVENT.json` | Serialize with nonblocking local lock, apply guarded event, persist receipt/state, return phase/version; duplicate exact event ID is idempotent |
| `effort-plan STORE PLAN.json` | Four scores, rationale and capability reference → accepted actual model/effort tier |
| `status STORE` / `packet STORE --cursor N` | Bounded manifest, used/reserved/remaining totals, current claim/frontier page, artifact/receipt pointers and next cursor |
| `fingerprint PROPOSAL.json` | Stable source-scoped generalized retro finding identity |
| `publication-check PROPOSAL.json` | Supplied privacy/approval/source/lookup/limits guard; no publication |

Every event has unique nonempty `id`, the existing `lineage` and `op`. A repeated
ID with changed content is rejected. Worker/action events additionally have `run`,
`ticket`, `owner`, `fence` and `action` matching the stored claim. Generate the
stable action ID before runner dispatch and reuse it for reconciliation.

| Event `op` | Additional required fields / evidence |
|---|---|
| approval | `receipt`: verified current human proposal approval or revocation; missing/stale status preserves approval pause |
| reserve | selected `ticket`, `owner`, stable launch `action`, `lease_until` Unix seconds, positive `allocation.tokens/seconds`, `effort.model/effort`, `plan.scores/rationale/capability` |
| launched | worker identity, `observed.model/effort`, hashed runner `evidence`; actual settings must match requested before work |
| result | worker identity, hashed result `evidence` and runner `terminal`; optional verified `usage.tokens/seconds`; unknown usage stays fully reserved |
| evaluate | worker identity, distinct `evaluator`, pinned `criteria` hash, all `checks`, hashed independent `evidence`, boolean `passed`, failure `signature` when false |
| reconcile | worker identity, hashed actual `terminal`, `outcome` cancelled/failed, optional verified `usage`; a lease timestamp is insufficient |
| settle-usage | worker identity, existing terminal receipt, hashed actual usage `evidence`, verified `usage.tokens/seconds`; reported/accepted status stays unchanged |
| checkpoint | hashed reproducible `prototype`; selected checkpoint independently accepted, no possibly active worker |
| trial | verified actual human `receipt` bound to prototype hash, `disposition` accept/resume/delta; delta preserves pause for separately approved successor |
| begin-action | worker identity, allowed `operation`, selected `target`, stable new `identity`; persist before actual authorized external mutation |
| action-result | worker identity, action `identity`, confirmed/uncertain `outcome`, hashed actual `evidence`; confirmed actions cannot replay |

`plan.scores` has exactly ambiguity/integration/consequence/validation, integers
0–2. The accepted policy owns their tier mapping; supplied capability evidence
owns available IDs/names. An escalation needs a revised evidence-backed score or
accepted mapping revision and remaining budget; family switching is separately
authorized. Full-history inheritance/settings limitations belong to the runner
adapter, and mismatch retains the claim for reconciliation.

Exit 0 returns JSON state/result. Exit 1 returns `status: parked` and a reason;
no requested event state is committed. Persist a consolidated exception and its
affected work in the private artifact index before another scheduling decision.
Continue only independent eligible authorized work; never spin on a rejected event.
After an uncertain external call, use actual tracker/runner/repository evidence to
settle its existing action, not a new identity to evade the ledger.

The private exception index uses `schema_version: 1`, `project`, `lineage` and
`entries`: each entry has `id`, `cause`, `affected_tickets`, `next_choice`,
`status` (open/resolved), `evidence` references and `supersedes` (ID or null).
Deduplicate a repeated cause/affected-set by updating its evidence pointer, not
opening a fresh human gate on every wake. The compact packet references this index;
material blockers remain discoverable even when detail is paged out.

The supervisor coordination JSON uses `schema_version: 1`, `project`, `lineage`,
`configuration` (accepted record reference), `registry` (reference), `owner`
(`id`, monotonic `fence`, `lease_until`, runner/task reference), `wake` (`id`,
`source`, `timestamp`, reconciliation evidence references), `approval` (current
verified receipt reference), `reservations` (global/project/wake allocation
references), `actions` (stable identity/outcome receipt references) and
`notifications` (deduplication key, destination, content hash, intended/confirmed/
uncertain outcome). Validate these fields/types/references against accepted setup
before relying on them. The coordinator/actual runner adapter owns this record;
the local worker-claim CLI does not create a scheduler or send notifications.

The state file is atomically replaced under the lock; an event receipt is saved
before state commit. A crash between them permits replay of the same local event;
external action calls happen only after a committed intended-action receipt.
An interrupted init that wrote only bundle.json is a parked recovery case: inspect
the matching bundle/no-action receipts, preserve it and restore state from the
recorded initialization evidence under coordinator authority. Never delete a
partially initialized store or overwrite its history to reset limits.

Artifacts referenced by this API must be regular files inside the accepted private
root with matching SHA-256. The adapter resolves symlinks into explicit immutable
artifact copies. Protect store and artifacts from implementer writes. Authenticate
human/runner/privacy sources before constructing input JSON. Single-machine flock
does not establish distributed exclusion or remote process cancellation.
