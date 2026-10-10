---
name: dark-factory-supervisor
description: Reconcile a bounded dark-factory wake and coordinate eligible authorized executor work through an accepted runner, preserving approval and user-trial pauses.
---

Find `dark-factory` by its catalog path or `<skills-root>/dark-factory/SKILL.md`
in the flat installed skill root. Read that leaf folder's references; verified
source-checkout fallbacks are
[contracts](../dark-factory/references/contracts.md) and
[adapters](../dark-factory/references/adapters.md). Use its control CLI for the same
admission/ownership/observation rules as direct execution; do not duplicate that logic.
Read [usage reporting](../dark-factory/references/metrics.md) for wake/worker
observations and durable per-project summaries.

Inputs: accepted registry/configuration (one project by default), actual runner,
periodic or manual wake, immutable authority, proposal approval and durable packet.
Cron is a wake trigger; durable state selects work. No platform API is assumed.

1. Load a fresh bounded packet and selectively verify authoritative records,
   source/skill/proposal versions, trusted approval, action rights and accepted
   schedule/runner/registry/concurrency/notification configuration. Configuration
   proposals do not create a schedule. Missing computer/access/credentials or
   capability blocks honestly; never report an unobserved executor launch.
2. Reconcile runner ownership, leases/fences, durable claims/reservations, callbacks
   and uncertain actions before dispatch. Duplicate ticks/multiple schedulers
   share the same project/run lineage and local lock or validated remote exclusion.
   Expiry alone never proves a worker stopped; observe runner terminal state before
   takeover. Reject stale owners/late callbacks by run/attempt/action/fence identity.
3. Respect concurrency and any configured wake/project/global caps, then start/resume only eligible
   authorized `dark-factory` work through the supported adapter. Supervisor builds
   nothing. Reuse stable action IDs and verified launch settings. A prior executor
   possibly alive or a launch with uncertain outcome means reconcile/park.
4. Preserve cumulative costs, repairs/no-progress, budgets and claims across wakes,
   retries, children and context handoffs. Configured cap exhaustion stops launches; observe-only records usage without
   user token/time/attempt caps. New IDs do not
   restore allocations. Use backpressure, finish this bounded wake and checkpoint;
   never hold a polling loop or recursively dispatch coordinators.
5. Persist per-item usage/timing/attempt receipts, write run reports and refresh
   the project aggregate at run stops. Deduplicate notifications by project/run/state/evidence
   identity. Notify only accepted destinations about meaningful progress, failure,
   completion or required approval/trial/user action. Calibration run-end statistics go to the accepted reporting route.
   No-op/unchanged wakes are silent.
   Apply the privacy contract to notification content as well as issue publication.

Preserve `awaiting-idea-approval` and `awaiting-user-trial` until actual direction.
Do not select the next target/backlog or treat silence as feedback. Setup/idea/retro
are separate authorized phases: a pause never authorizes rerunning them. Optional
retro is separately bounded and starts no build. Completion is reconciled durable
state and any warranted deduplicated notification, not a continuous background run.
