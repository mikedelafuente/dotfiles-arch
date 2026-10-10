# Factory guidance — revision 5, proposed

Load this guidance for planning, execution, evaluation, resume and retro. The
hashed setup index identifies the proposal; acceptance is still required.

## Project boundary

Deliver small, reviewable improvements to Arch and Ubuntu workstation automation.
A first outcome/spec remains a human choice. Preserve modular Bash setup scripts,
one additive profile runner, the stable installed-generation boundary, and existing
ADRs. Shared changes belong in the checkout verified by `dfa-deploy source`.
Keep saved config behind the library helpers, use `USER_HOME_DIR`, retain package
and update owners, preserve foreign files, and keep required failures observable.
Read `CLAUDE.md`, relevant `.cursor/rules/`, `PACKAGES.md`, `docs/deployment.md`,
and the area-specific source audit/validation inventory before changing behavior.

Validation uses static checks and supplied facts in temporary fixtures. Run the
smallest relevant decision check; shell changes require `bash -n` and
`shellcheck -x`, with `bash scripts/check.sh` as the repository gate. Runtime
claims require actual evidence; record hardware, desktop and transport gaps.
Workstation setup, deployment, migration, packages, services, drivers and OS/VM
provisioning remain outside factory validation authority.

## Planning and tracker

When the council plans environment improvements, consult
[environment inspiration](../market-research/environment-inspiration.md) for
workflow priorities and research sources. For vague prompts or goals, use relevant
creator examples or articles to develop concrete options. Specific articles and
video timestamps are optional; include them when they clarify an option or resolve
uncertainty. Treat the note as planning guidance within the accepted scope and
authority.

Use the parent-issue resolver in `tracker.json`, subject to its outstanding contract
acceptance. For future approved changes, the user selected one parent GitHub issue
with native sub-issues and dependency links. No new parent or outcome is selected.
Historical milestone selections and approvals remain unchanged. A document called
an idea is an artifact, not a new tracker object type. Resolve bounded membership,
descendants, exclusions and dependencies before proposing tickets. Freeze all
mandatory criteria and explicit prototype/trial checkpoints before approval.
Material scope, architecture, risk, budget or publication changes need renewed
human approval; routine grooming retains equivalence evidence.

## Execution and evaluation

Use one integration branch and owned scoped workers after admission.
Discover installed `implement-spec`; compose its worktrees, TDD and merger only
within accepted policy. Its upstream issue-closing steps require separate actual
publication authority here. Use the existing independent Standards/Spec review
once; an implementer's success summary cannot establish acceptance. Keep pinned
imports intact. No nested coordinator or recursive review council.

Before launch, the coordinator validates hashes, current human receipts, exact
runner settings, ownership/fence and the observe-only accounting route. Failed settings or
uncertain launches retain reservations. Record unavailable usage telemetry as
missing. Park unsupported isolation, terminal confirmation, verifier or fencing
paths; configuration alone does not supply them.

## Calibration and usage reports

For initial calibration runs, use no user-set token or wall-clock cap. Preserve
platform/session limits, approved scope, review, recorded attempts/repairs,
no-progress stops and the human trial pause. Keep cumulative usage across resumes.
After every completed, blocked or interrupted run, report parent issue/run/ticket,
agent/model/effort, phase, input/cache/output/reasoning usage, elapsed time,
attempts, repairs and outcomes. Use actual usage evidence; label unavailable
metrics and avoid double-counting cached/reasoning subsets. Report money only
when rates and billable usage are known. After several runs, compare sample
count, median, mean and range before proposing calibrated limits.

The source control CLI supports observe-only calibration. Follow its
[usage reporting contract](https://github.com/mikedelafuente/skills/blob/bd00537de1d7ae4150980f49a2a7af11da9fd970/skills/mikedelafuente/dark-factory/references/metrics.md):
record each authorized work attempt once, write per-run reports, and refresh the
private project aggregate. Capture actual runner usage when available; missing
measurements alone do not stop uncapped calibration. Preserve claim/fence,
approval and trial guards. Pin the updated controller/skills before admission;
source fixture proof does not certify live runner or approval adapters.

## Artifacts, handoff and stops

Commit public setup proposals here; keep private run detail in the proposed
0700 artifact root from `authority.json`, outside worktrees. Only the coordinator
writes state. Workers need enforceable read-only snapshot access and scoped code
write access; same-user filesystem permissions alone do not isolate workers.
Copy every admitted reference into regular immutable artifacts under the accepted
root; installed skill symlinks are discovery pointers, not admissible artifacts.
Record skill/source SHA-256, base/worktree identity, criteria, launch observations,
usage, results and independent evaluation references there.

Checkpoint at phase boundaries and before 80% of the context allowance. Resume
from a bounded packet with authoritative ownership/action/usage reconciliation.
An uncertain worker stays reserved; lease expiry alone permits no takeover.
Unsupported fresh-context transfer means a checkpoint and human handoff.

Stop at the selected prototype checkpoint and await actual human trial disposition.
Completion requires every selected descendant independently accepted and the
required trial disposition; closing a parent is insufficient. Retain run
history through worktree cleanup; propose 90-day retention after completion and
explicit human authorization for deletion. Retro has separate accepted limits and
source-scoped publication authority. No automatic next-goal selection.
