---
name: dark-factory-idea
description: Refine an idea or prototype change into a bounded versioned spec and ticket graph, then await human idea approval. Use within an accepted dark-factory project.
---

Find `dark-factory` by its catalog path or `<skills-root>/dark-factory/SKILL.md`
in the flat installed skill root. Load that leaf folder's references; verified
source-checkout fallbacks are
[contracts](../dark-factory/references/contracts.md) and
[adapters](../dark-factory/references/adapters.md). Read accepted charter, council,
guidance, ADRs and authority; validate their identities. Missing, conflicting or
changed grouping configuration routes to `setup-dark-factory`, not a new tracker
interview on every idea.

Read the resolved dark-factory leaf's [usage reporting](../dark-factory/references/metrics.md)
when recording planning/council/research effort. Initial calibration proposes
observe-only usage reporting; a finite selected graph does not require resource caps.

Inputs: broad idea or change request, accepted project records and, for a delta,
the current verified prototype. Idea invocation starts no implementation.

1. Inspect the actual project and prior evidence. Use a bounded human clarification
   phase through `grill-me` → `grilling` or `advise-me` → `advising` →
   `grilling`/`agent-council`. Preserve real answers and unanswered choices; confirm
   shared understanding. A broad incomplete prompt does not establish direction.
2. Once direction is accepted in explicit dark-factory mode, council handles routine
   refinement and ticket grooming within the charter. Consolidate material intent,
   scope, authority, data and architecture choices for the human. Direct upstream
   skills and interactive mode keep their normal checkpoints.
3. Compose `research`, `agent-council`, `council-handoff`, `to-spec`, `to-tickets`.
   Reuse adequate evidence and existing issues. Specify actors/journeys, scenarios,
   scope/non-goals and applicable security, accessibility, performance, reliability
   and operations needs. Keep facts, assumptions, proposals and dissent distinct.
4. For a delta, inspect the checkpoint, affected modules/journeys, dependencies,
   compatibility, data/schema consequences and regressions. Preserve earlier
   acceptance unless explicitly superseded. Material architecture/database changes
   require actual direction and a reviewable plan for compatibility, retention,
   backfill, sequencing, validation and rollback/recovery. Production access,
   destructive migration and data deletion require their own authority.
5. Freeze a bounded proposal and dependency-linked ticket graph using the accepted
   resolver. Separate the selected delivery goal from the wider deferred backlog.
   Propose demonstrable intermediate checkpoints and hands-on trial expectations.
   Record council-qualified readiness separately from approval and action rights.
   Apply the four-score model/effort contract; retain existing `execution_guidance`
   and user edits. Publication/assignment needs destination/action authority;
   otherwise save private draft tickets and parent summary.
6. Present outcome, scope, material architecture choices, risk, observation/configured budget policy and
   checkpoints with an exact revision/hash. Record actual authenticated approval
   only through the accepted verifier; stop in `awaiting-idea-approval` until it
   matches. A label, assistant text, silence or wake is not approval. Material
   changes need a new approved revision; equivalent routine grooming records its
   relationship to the existing approval without another gate.

Completion: versioned spec/delta, bounded graph, effort plan, evidence and dissent,
blockers, approval status and authority references. Preserve per-item planning
usage/timing/attempt receipts for the project aggregate, with missing telemetry explicit. Archive interview/research detail
behind durable pointers. Hand off to a direct authorized `dark-factory` invocation
or an explicitly accepted supervisor; this skill starts no build, commit, push,
PR, merge or deployment.
