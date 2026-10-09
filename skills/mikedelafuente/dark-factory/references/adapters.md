# Adapter boundary

## Skill resolution and composition

Resolve an exposed installed name first with the harness skill tool. If absent,
look for exact `SKILL.md` in project `.agents/skills`, configured harness skill paths
and the source fallback below. Follow supporting resources relative to the resolved
skill. Missing dependencies/capabilities become scoped gaps, never invented tools.

| Installed name | Relative source fallback from dark-factory |
|---|---|
| setup-dark-factory, dark-factory-idea, dark-factory-retro, dark-factory-supervisor | `../<name>/SKILL.md` |
| agent-council, council-handoff, advising, advise-me, review-changes, adversarial-code-review | `../<name>/SKILL.md` |
| implement-spec, implement, tdd, research, to-spec, to-tickets, retro | `../../mattpocock/engineering/<name>/SKILL.md` |
| grill-me, grilling, writing-for-agents | `../../mattpocock/productivity/<name>/SKILL.md` |

Load only the current phase's dependencies. Keep pinned imports unchanged.
Interactive/direct upstream invocation retains its own gates. In an explicitly
accepted dark-factory mode, this personal adapter substitutes council decisions
only for routine interview/seam/breakdown checkpoints within accepted direction.
It preserves material human gates and each actual unanswered choice. Compose
`implement-spec` pointers, scoped implementers and merger under the action policy,
then the existing independent Standards/Spec review once; no nested review council.

## Tracker resolver (accepted per repository)

Setup records `tracker`, repository/project identity, target kind, exact object and
label IDs, native query, descendant traversal, dependency resolver, exclusion rules,
finite member/depth bounds, completeness evidence, completion and trial stops.
Idea/executor reuse that identity. Only absent/conflicting/changed configuration
goes back to setup/reconciliation. A native GitHub milestone is a proposal when no
convention exists, never a platform-selected default.

Supported supplied-data examples include GitHub native milestone, an issue
designated by an exact milestone label, Jira native/labeled epic, and company Idea
objects grouping epics. Their hierarchy/membership APIs differ; a resolver must
explain actual semantics and evidence of complete pagination/descendant traversal.
Ambiguous label ownership, unbounded query, absent hierarchy or inaccessible
dependencies blocks affected work. No universal Jira hierarchy is claimed.

Freeze selected membership, nested descendants/dependencies and native versions.
Keep excluded backlog and unmet external prerequisites explicit. Parent closure
does not imply descendant acceptance. Reconcile additions/relationship changes
boundedly; scope changes need explicit direction and a successor snapshot.
Publishing targets, assignment, comments, closing/status changes and PR operations
each require the actual tracker-specific permission. Use current primary API docs
when implementing an adapter; this package ships no network adapter or credentials.

## Effort and runner contract

Discover actual allowed family, model IDs, effort names, settings inheritance,
scoped-context support, telemetry, cancellation/terminal observation, checkpoints
and exclusive-owner/fencing capability. Save capability source/version/date. The
families in the requested contract are Sol 6.1 and Opus 5.5; use only IDs actually
supplied by the runner and allowed by policy. Do not assume Opus is available or
that runner effort names coincide. Unsupported settings are parked, not silently
remapped. Family switching requires its own authority.

Score each of ambiguity, integration complexity, consequence and validation
difficulty from 0 (routine) to 2 (material). Setup proposes and obtains acceptance
of a mapping from the four-score total to supported model/effort names. Scores are
heuristics, not measured performance. Record the four scores, rationale, capability
reference and the exact requested setting. Escalation needs a specific reason and
remaining budget; maximum effort is not automatic.

Append/merge a parseable block into tickets without erasing existing guidance:

```json
{"execution_guidance":{"schema_version":1,
 "scores":{"ambiguity":1,"integration":1,"consequence":0,"validation":2},
 "requested":{"model":"<allowed supplied ID>","effort":"<supported name>"},
 "rationale":"Cross-system validation requires the accepted higher tier",
 "capability_ref":{"path":"<artifact>","sha256":"<hash>"}}}
```

Parent summary points to ticket guidance and budget allocation. Record requested,
resolved and actually observed launch settings plus runner/task/action identity.
Annotations are not proof. Full-history forks can inherit settings and reject
overrides: select a supported authorized scoped launch route or park/disclose it.
Verify settings before implementation; mismatches fail admission and retain the
possibly active claim until reconciled. Independent reviewers use separate contexts.

## Supervisor adapter

Accept schedule/runner/registry (one project initially), wake/project/global limits,
action routes, verifier, notification destination/content and checkpoint policy
before enabling them. A generic cron-capable assistant can wake the supervisor;
this package creates no schedule and assumes no Dots/OpenClaw/Muse/Claude API.

Each wake loads a bounded packet and reconciles ownership/usage/actions first.
Serialize a local project store with the CLI lock. For multiple machines, use a
validated distributed lock/lease with monotonic fence and compare-and-swap writes;
absent that capability, no distributed dispatch. An expired lease still requires
actual terminal evidence before takeover. Validate current fence immediately before
external actions; reject late callbacks and retain uncertain reservations.

Enforce global/project/wake backpressure outside the per-run seam with an accepted
shared registry reservation. A wake is finite and returns after receipt persistence.
No busy loop, replacement executor while another may live, or recursive supervisor.
Computer offline/credentials/capability gaps are blocked outcomes, not claimed runs.
Unknown usage conservatively retains the full reservation. Use an absolute deadline
and cancellation/terminal receipts; a restart cannot reset usage or repair counts.

Deduplicate notifications by project/lineage/state/evidence identity in the accepted
registry, with intended/confirmed/uncertain receipts. No-op/unchanged wakes are
silent. Meaningful progress, completion or required user action is sent only to the
accepted route with permitted content. Preserve both approval and trial pauses;
only actual user direction selects another delta/target or resumes selected work.
