---
name: setup-dark-factory
description: Establish or reconcile a project's dark-factory council, guidance, tracker convention, and proposed authority. Use when configuring a project for bounded autonomous delivery.
---

Find `dark-factory` by its catalog path or `<skills-root>/dark-factory/SKILL.md`
in the flat installed skill root. Read that leaf folder's `references/contracts.md`
and `references/adapters.md`; verified source-checkout fallbacks are
[contracts](../dark-factory/references/contracts.md) and
[adapters](../dark-factory/references/adapters.md). Resolve dependencies as specified
there. Missing records or capabilities remain explicit gaps.

Inputs: project path, goals, existing instructions/decisions, tracker configuration,
available skills and harness capabilities. This invocation establishes proposals;
it does not start a build or schedule.

1. Inspect actual code, use cases, docs, ADRs and instructions. Discover
   `agent-council` and `implement-spec`, including `.agents/skills` and personal
   harness paths when the catalog is incomplete. Preserve imports and user edits.
   Resolve AGENTS.md symlinks before writing: edit only a confirmed project-local
   target, or propose a project-local pointer separately when its target is shared.
   Reconcile a marked navigation block on repeats; rejected setup stays proposed.
2. Propose a charter, `COUNCIL.md`, project factory guidance and separate authority
   policy using the versioned record contract. Reuse existing adequate records.
   Council remits include BA (domain evidence/business acceptance) and PM
   (direction/value/priorities); add technical integration, architecture and
   engineering remits where needed. For each question use the smallest relevant
   set, record omissions, alternatives, dissent and missing/timed-out coverage.
   Label independent agents versus single-agent lenses honestly. Bound challenge
   rounds and follow-ups; evidence resolves disagreements, votes do not validate.
3. Reuse research before scoped primary-source research. Reference projects need
   URLs, access dates, versions, applicability, limitations and uncertainty.
   Preserve actual architectural preferences; a modular monolith is an example,
   not a universal default. Keep project-specific rules in project guidance.
4. Discover this repository's documented tracker hierarchy and grouping convention.
   Propose missing choices together, obtain actual human acceptance and persist the
   exact resolver contract. GitHub does not imply milestones; Jira does not imply
   a universal epic hierarchy. Record target/object/label IDs, queries, nested
   descendants, dependencies, exclusions, bounds, completion and trial stops.
   An artifact describing an idea is distinct from a tracker object named Idea.
5. Propose finite budgets, scoring-to-effort mapping, context limits, artifact
   storage/access/retention, supported scoped workers and checkpoint/handoff route.
   Propose supervisor runner/schedule, one-project registry, concurrency, operations,
   approval verification and notification destination. Discover capabilities;
   configuration is not permission to create a schedule or publish tracker objects.
6. Present the plain setup summary and version/hash-bound charter, council, guidance,
   ADR and authority references. Obtain explicit charter/guidance acceptance before
   autonomous reliance. Authority and optional scheduling/notification acceptance
   are separate. Generated files, council agreement and timeout are not acceptance.
   Validate required fields, references and versions with the control CLI before
   handing off. Link records from a concise AGENTS.md navigation block with loading
   conditions: planning, execution, evaluation, resume and retro.

Completion: proposed or genuinely accepted records, actual answers, capability
gaps, unresolved choices and versioned pointers. Optional phased targets and trial
checkpoints remain proposals until tracker-specific publication authority exists.
Next: `dark-factory-idea` on user-supplied intent after setup acceptance.
