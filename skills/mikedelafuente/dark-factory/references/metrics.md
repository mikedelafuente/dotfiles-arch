# Usage reporting and calibration

Read during setup, planning, dispatch, evaluation, resume and retro when recording
or reporting measurements. Start with `policy.budget_mode: "observe-only"` and
null tokens/seconds/attempts/repairs/deadline unless the user requests caps.
Concurrency, selection/context bounds, no-progress, approval and trial stops
remain. Legacy bundles without a mode retain bounded behavior. Observation does
not grant permission to execute or publish.

## Storage and identity

Use one private project artifact root outside worktrees. Store each durable run
under `ROOT/runs/LINEAGE/RUN/`; keep its bundle, state and committed receipts after
worktree cleanup. Resume that same store. The coordinator is the sole writer.
The CLI's existing per-event receipts are the measurement ledger; no external
metrics service or parallel mutable accounting ledger is needed.

Each independently executed item/attempt has a stable identity, project,
lineage/run/selected target, ticket (or null for project planning), phase,
owner, attempt ordinal, requested and actually observed model/effort, outcome,
usage and evidence. Retries keep separate action IDs and attempt rows. Model
mismatches remain launch failures; an unobserved model is unknown, not requested.
Use phases such as council, research, planning, implementation, evaluation, repair,
supervisor and retro. Keep project-specific task categories in the item label.

Implementation launch/result/settlement receipts already describe each attempt.
Record `activity` for council/research/reviewer/merger/supervisor/retro work that
has no implementation claim. Record after authorization and execution, not as a
launch permit. Save pre-init planning observations privately and import them once
its actual run store exists; keep their original runner timestamps/evidence.
Each activity represents ONE attempt. A retry gets a new identity and incremented
attempt ordinal. Never record the same implementation attempt again as activity.
Use exclusive agent usage: children get their own rows, while parents exclude
child totals. If runner counters are inclusive and cannot be separated, identify
coverage in evidence, record only disjoint measured rows and mark parent usage
unknown. Summaries never add a parent rollup as another executed item.

## Usage and timing fields

`usage` contains `tokens` (nonnegative integer) and `seconds` (nonnegative finite
number, exclusive active-agent time). In observe-only, either may be null when
unavailable. Optional integer/null categories: `input_tokens`,
`cached_input_tokens`, `cache_write_tokens`, `output_tokens`, `reasoning_tokens`.
Input/output totals include their cache/reasoning subsets when the provider
reports them that way; adapters normalize provider semantics first. Total tokens
are input + output, never that sum plus cached/reasoning categories. Unknown is
null, never a guessed zero. The report names missing-item coverage explicitly.

Optional `timing: {started_at, finished_at}` uses actual runner Unix timestamps,
including fractional seconds. Require end >= start; store the source evidence.
Wall elapsed and active-agent time are separate: do not sum concurrent wall
intervals and call that milestone elapsed. The CLI adds `_received_at` to receipts
for approximate coordinator callback timing when runner clocks are unavailable.
Legacy receipts with no clocks have missing wall timing, not manufactured dates.

`settle-usage` fills unknown observations later, even for an archived retry. It
cannot change known counters; exact callback replay is idempotent. Statistics
must retain interrupted/failed attempts and telemetry gaps, not only successes.
Do not claim precise dollars without actual billable categories and known rates.

Example independent review measurement (supplied runner facts, not authorization):

```json
{"id":"review-metrics-1","lineage":"change-1","run":"run-1","op":"activity",
 "identity":"review-attempt-1","item":"ticket-a standards/spec","ticket":"ticket-a",
 "phase":"evaluation","owner":"reviewer-a","attempt":1,
 "model":"actual-supported-model","effort":"actual-supported-effort",
 "outcome":"completed","usage":{"tokens":null,"seconds":12.5},
 "timing":{"started_at":100,"finished_at":115},
 "evidence":{"path":"review-runner.json","sha256":"actual-evidence-hash"}}
```

## Reports and future tuning

After each completed, interrupted or blocked run, run:

```text
python3 <dark-factory>/scripts/control.py report STORE --write
python3 <dark-factory>/scripts/control.py report-project ROOT --write
```

These save private `usage-report.json` files in the run store and project root;
stdout contains hashed report pointers and compact totals. Without `--write`, the
full JSON is returned. Project aggregation scans committed run stores, deduplicates
identical copies of one project/lineage/run and parks conflicting copies. Receipt
hash drift parks reporting rather than silently changing measurements. On-demand
snapshots may contain runs at different lifecycle points; each run records its phase.
Keep raw receipts as the durable source; regenerated reports replace summaries only.

Reports include every measured item/attempt, per-item attempt/usage rollups, a
coordinator-receipt run timeline (including waits), and project/model/observed-effort/phase
groups with known totals, measured/missing counts, mean, median, min and max for
tokens, active seconds, elapsed seconds and token categories. Requested/observed
settings, evidence, outcomes and selected target stay on item rows. `attempts`
counts recorded work attempts, not terminal callbacks, replays or numbered phases.
Milestone end-to-end duration includes human waits; use the run timeline/evidence,
not summed worker wall durations, to describe it.

Send a short end-of-run summary through the accepted reporting route, with tokens,
time, attempts, outcomes, measured coverage and report pointers. After several
runs, compare similar project items and efforts using both successes and failures.
Keep sample counts and telemetry gaps visible. Propose caps or effort changes only
from this evidence and actual user direction; this package does not auto-tune them.
