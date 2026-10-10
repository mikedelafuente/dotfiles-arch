# Shared contract, version 1

Load this contract at setup, planning, admission, evaluation and resume. The five
entrypoints share it; project-specific choices belong in accepted project records.

## Records and trust

Use UTF-8 JSON for machine records and Markdown for human guidance. Each reference
is `{path, sha256}` with a regular readable artifact and its byte hash. Store
private detail outside temporary worktrees in the accepted artifact root. Paths
alone are not identities. Snapshot all references before launch; edited bytes or
missing artifacts park affected work. Reject incompatible `schema_version`.

The project record set contains:

| Record | Required contents |
|---|---|
| Charter | Goals/non-goals, explicit interactive/dark-factory mode, operating boundaries, council/guidance/ADR identities, separate authority pointer, actual acceptance receipt |
| Council | Domain/actors/use cases, BA/PM and relevant technical remits, omissions, evidence ownership/references, bounded disagreement and honest independence coverage |
| Guidance | Platform/workflow, validation restrictions, quality and architecture preferences, accepted ADRs, accepted repository-specific tracker adapter |
| Decision ledger/ADRs | Actual answers/direction, accepted decisions, proposals/assumptions/dissent/evidence separately; superseded ID, reason, impacted requirements and acceptance receipt |
| Authority | Scope, allowed actions/resources/models, publication destinations/content, optional resource caps, observation/reporting and stop rules, trusted verifier and human acceptance |
| Coordination | Accepted registry, runner/schedule, project/global/wake concurrency, notification route, approval verifier, stable lineage/storage, lease/fence and deduplication records |
| Proposal | Revision/hash, outcome/scope/material architecture constraints, budget/risk/publication/checkpoints, frozen criteria, spec/ticket graph and approval relationship |
| Run | Frozen references/selection/criteria/source/skills, actual launch settings, per-item usage/timing/attempts, claims/actions, budget/repair history, independent evaluations, prototype and trial disposition |

`scripts/control.py init STORE BUNDLE.json` checks the machine envelope described
below. It does not create or accept these human records. The coordinator validates
their semantic contents against the table and repository instructions before init.
Keep concise AGENTS.md loading pointers; preserve project-local symlinks and user
edits. Never write through a shared/global target. Repeated setup reconciles only
its marked material, and rejected proposals remain unaccepted.
Read [operations.md](operations.md) when constructing CLI inputs, reconciling a
callback or handling a parked result. Its event field table is the machine API.

Acceptance receipts identify actor, source, timestamp, subject hash and current
status. A configured adapter verifies authentication, source identity, revocation
and freshness against actual human evidence. The CLI consumes these verified facts
through its trusted input boundary; it cannot authenticate arbitrary chat JSON.
Protect the store from workers (private permissions; coordinator is sole writer).
Never accept a worker's `verified=true`, a label, assistant text or copied signature
as proof. Reconcile the current authoritative receipt before every admission.
Record the verifier identity/source in the accepted authority. Council readiness,
idea approval, action permissions and spending allocations are distinct.

Material outcome/scope/architecture/budget/risk/publication changes require a new
proposal and renewed approval. Routine equivalent grooming retains the approved
proposal identity and archives its equivalence evidence. Policy/ADR changes never
rewrite an active immutable snapshot; park dependent work and create a traceable
accepted successor retaining lineage and budget history. Higher-priority project
restrictions remain binding. Consolidate conflicts; do not invent precedence.

## Machine envelope

The CLI is a local deterministic seam, not a runner, tracker, authenticator or
general-purpose workflow engine. It executes no project commands and uses only
stdlib. Call `python3 <resolved-skill>/scripts/control.py --help` for operations.
Read [adapters.md](adapters.md) before connecting a runner. Use the single accepted
store per project/iteration lineage across wakes and resumes. Its lock covers a
local filesystem only; remote/distributed scheduling needs validated exclusion.

A bundle has `schema_version: 1`, nonempty `project`, `lineage`, `run`, and:

- `records`: charter, council, guidance, authority, proposal, criteria, source,
  skills and decision-ledger references. Each reference includes `path`/`sha256`.
  `accepted` holds charter/guidance/authority receipts; authority also requires
  council/decisions/coordination acceptance where the project contract calls for it.
- `policy`: `budget_mode` (`observe-only` for initial calibration, or `bounded`), `actions` (explicit operation names), `models` (model ID → supported
  effort strings), `families` (model ID → `sol-6.1` or `opus-5.5`), accepted
  `effort_mapping` (ascending inclusive `max_score` tiers ending at 8 with actual
  `model`/`effort`), `verifier`, `approval_sources`, `limits` (`tokens`, `seconds`,
  `attempts`, `concurrency`, `queue`, `repairs`, `no_progress`), `deadline` (Unix
  seconds or null), `context` (`entries`, `bytes`) and `artifact_root`. In
  `observe-only`, tokens/seconds/attempts/repairs and deadline may be null: no
  user-set cap. Explicit positive caps still apply. Concurrency/queue/no-progress
  and context bounds remain positive; scope, approval and trial stops still apply.
  An omitted mode retains legacy `bounded` behavior with all finite limits.
  Setup proposes observation first, without arbitrary task/run/wake resource caps.
  This must equal the referenced authority JSON's `policy`.
- `selection`: adapter reference, exact target kind/identity, ticket IDs, complete
  descendant IDs, exclusions, dependency IDs by ticket, already satisfied external
  dependency evidence, `complete` hierarchy evidence and `checkpoint` ticket IDs.
  Dependencies are finite and acyclic. Parent/descendant membership is explicit;
  the CLI does not infer native tracker relationships. All selected descendants
  must be included in `tickets`. Adapter evidence certifies the snapshot is complete.

Initialize only after semantic validation. The CLI stores immutable `bundle.json`,
mutable `state.json`, and indexed per-event receipts. Hash verification catches
record drift; complete selected history stays on disk. `packet` returns a measured
bounded scheduling manifest with versioned pointers, paged claims/frontier and
budget totals. Use its cursor for additional pages; a small limit produces an
exception instead of silently dropping blockers. Archives must outlive worktrees.
The checkpoint/prototype reference includes its reproducible command instructions,
prerequisites, code/content identity, frozen acceptance/regression results, known
limitations, runtime-unverified coverage and measurement provenance/gaps.

## Lifecycle and owners

| State | Guard / owner / exit |
|---|---|
| preparing | Coordinator validates accepted records, frozen graph/criteria, capability and authority; missing approval/scope data blocks; configured caps apply |
| awaiting-idea-approval | Idea proposal presented; coordinator records only verifier-backed matching current human receipt |
| ready | Matching approval, checked records and at least one dependency-satisfied authorized ticket; reconciled owner and allocation before dispatch |
| running | Coordinator reserves a claim and stable action ID before calling runner; implementer starts only after observed settings match |
| evaluating | Implementer has reported artifacts/usage; separate evaluator receives pinned criteria/diff/evidence independently |
| repairing | Failed criterion has a targeted repair with remaining run/child/repair/no-progress allocation; original criteria remain frozen |
| blocked | Durable cause/affected tickets/next choice; independent eligible work can continue, blocked dependent work cannot |
| budget-exhausted | Configured deadline or enclosing budget exhausted: no new launches; retain reservations and all usage |
| awaiting-user-trial | Independently accepted selected checkpoint, reproducible prototype handed off; preserve this pause across every wake/resume |
| completed | Every selected descendant accepted, required evidence and actual trial disposition; unresolved work cannot complete |

Store owners and guards in event receipts: coordinator owns selection/claims/budgets,
implementer owns code/artifacts, independent evaluator owns acceptance, human owns
approval/trial/architecture/scope direction. `evaluate` requires a different agent
identity, frozen criteria hash, coverage of every frozen required check, result
artifact and recorded pass/fail; missing coverage is a failure, not acceptance.
Reuse the existing Standards/Spec owner once without recursive coordinators.

`reserve` counts each implementation attempt and claims the item before launch.
In observe-only mode, uncapped allocations are null; missing usage is reported as
missing, never zero, and does not block retries once terminal evidence is present.
Configured finite caps retain reservation/overrun behavior and require sufficient
remaining allocation. Children obey configured deadlines; waits do not extend them.
Use [usage reporting](metrics.md) to record each council/research/implementation/
review/repair/retro item once, with observed effort, tokens, timing and attempts.
Store per-run reports and aggregate by project/model/effort/phase for later tuning.
Resumes retain receipts and retry history. Measurement gaps alone do not prevent
uncapped calibration; actual launch/action uncertainty still parks affected work.

Callbacks carry lineage/run/ticket/action/fence/owner identity. Stable reservations
survive interruption. Reconciliation needs actual runner terminal evidence before
lease takeover; expiry alone is insufficient. Uncertain launch/action remains
reserved and parks retry. Late stale callbacks are rejected. Action receipts record
intended operation/target, stable identity, attempt and confirmed/uncertain outcome
before another mutation; confirmed actions are not replayed. Cancelling a worker
requires runner capability/authority and terminal confirmation, then conservative
usage settlement. Failure signatures bound repeated/no-progress repair attempts.

The control seam gates admissions and local state. Adapters gate actual mutations
immediately before calling external tools; they check the fence/owner/authority and
record the resulting receipt. The CLI cannot stop an already running remote process.
If an adapter cannot enforce these rules, park the action instead of bypassing them.

At a selected intermediate or goal checkpoint, hand off a testable prototype and
pause. Actual trial acceptance/disposition is separate from machine acceptance.
Explicit resume may continue the remaining selection; feedback requesting material
changes creates a new bounded approved delta while retaining budgets and regressions.
Silence never resumes, selects another goal, closes tracker targets or promotes a
prototype to production. Retro has separate limits and cannot change build success.

## Context and recovery

Keep the coordinator manifest below accepted entry/byte limits. It includes state,
snapshot identity, budget totals, current frontier/claims page, receipt index and
material-exception pointers; archive completed detail. Do not copy full histories,
logs/diffs or interview transcripts into worker packets. Each worker/evaluator gets
only assigned criteria, necessary immutable guidance/authority/ADR/dependency refs,
base/worktree identity, actual effort and allocation. Evaluators can load raw pinned
evidence independently, not only the implementer's success summary.

Checkpoint before the retained-context threshold and at phase/scheduling boundaries.
Supported fresh-context handoff loads the compact packet then selectively validates
authoritative graph/records, ownership, in-flight usage and action outcomes. Missing
or stale pointers cause bounded revalidation or parking. Unsupported handoff means
checkpoint/pause with disclosed limitations, not recursive spawning to reset limits.
Compaction may still occur; correctness must survive loss of the original chat.

Human summaries carry outcomes, blockers and next choices. Detailed records carry
concise rationale, dated/versioned evidence IDs, actual answers, proposals,
assumptions and dissent. Neither output includes private reasoning transcripts.
