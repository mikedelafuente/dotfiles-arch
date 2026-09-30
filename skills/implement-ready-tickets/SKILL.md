---
name: implement-ready-tickets
description: "Run a persistent goal to implement and squash-merge a fixed batch of open ready-for-agent tickets sequentially, with TDD, delegated Standards and Spec reviews, dependency tracking, and safe cleanup. Use when asked to work through the ready ticket queue without routine sign-off."
---

# Implement ready tickets

Complete the initial batch of open `ready-for-agent` tickets in the target repository.
Explicit invocation to execute this workflow authorizes commits, pushes, PR creation,
and squash merges without routine sign-off. Creating or editing this skill does not
start a batch. Automatic discovery alone does not grant merge authorization.

## Start a persistent goal

Explicit invocation to run this skill is a request to create a persistent goal, not
just to execute one turn. Before implementation, inspect the thread's goal with
`get_goal`. If no unfinished goal exists, use `create_goal` with this objective:

> Implement and squash-merge every ticket in the initial open ready-for-agent snapshot
> using implement-ready-tickets. Work sequentially with TDD, delegated Standards and
> Spec reviews, required checks, safe cleanup, and a durable progress record. Continue
> across turns until all initial tickets are verified merged; if none of the remaining
> tickets can proceed safely, record and report blockers without claiming completion.

Reuse an existing goal for this batch, including one established by `/goal`; do not
replace an unfinished unrelated goal. Report that conflict before starting a new batch.
Set a token budget only if the user explicitly requests one. Never create a goal merely
because the user asks to create, edit, or explain this skill.

At each continuation, inspect goal state and reconcile the durable progress record;
continue the same snapshot and active ticket. A turn ending is not batch completion.
Honor user pauses and runtime budget limits. If goal tools are unavailable, explain
that cross-turn continuation cannot be guaranteed and provide this invocation for a
goal-capable Codex session: `/goal Run $implement-ready-tickets to completion`.

## Prepare and snapshot

1. Read the repository's `AGENTS.md` and applicable rules. Read
   `mattpocock-skills:implement`, `mattpocock-skills:tdd`, and
   `mattpocock-skills:code-review` from the available skill catalog or installed sources.
   Use their instructions throughout; this workflow overrides their routine sign-off
   prompts: choose and record behavior-based public test seams independently.
   If a required skill or delegated reviewer capability is unavailable, record the
   blocker rather than silently substituting a different workflow.
2. Resolve the target repository and its issue-tracker instructions, including
   `docs/agents/issue-tracker.md` when present. For GitHub, resolve the owner/repository
   with `gh repo view --json nameWithOwner`. Use the repository's documented eligibility
   convention; absent another convention, select open issues labeled `ready-for-agent`.
   Retrieve every result, including pagination. Never treat a failed query as an empty
   queue or guess at an ambiguous repository or eligibility convention.
3. Inspect the working directory, branches, worktrees, open PRs, and relevant running
   services/test resources before allocating anything. Preserve other tasks' changes,
   unpublished commits, branches, worktrees, fixtures, and infrastructure.
4. Snapshot eligible issue IDs and URLs, creation times, explicit priorities, and
   specification contents at the start. This immutable membership is the whole batch;
   newly eligible tickets and prerequisites outside it are excluded.
5. Read each ticket's specification, comments, parent issues, and dependencies. Record
   acceptance criteria and dependency edges. Reading an out-of-batch prerequisite
   does not authorize implementing it. Treat missing access or unresolved dependency
   status as a blocker, not proof of readiness. Revalidate specifications before work;
   do not implement a ticket that has been closed, withdrawn, or made ineligible.

## Durable record

Before implementation, create a uniquely named progress record outside tracked project
files, in a persistent location shared across this task's worktrees (for example,
`<git-common-dir>/agent-batches/<unique-batch-id>/progress.md`). Record its absolute path
and update it before and after resource allocation and every status transition.

Keep the following in the record:

- Target repository, batch ID, snapshot timestamp, immutable issue membership, and queue.
- Goal objective/state and consecutive goal turns with the same batch-wide blocker.
- Specifications, acceptance criteria, priorities, dependency graph, and chosen test seams.
- Per-ticket state: pending, active, blocked, merged, or externally resolved, with evidence.
- Validation commands/results, review findings and resolutions, base and reviewed head SHAs,
  PR URLs, check results, and merge commits.
- Blockers and what would resolve them; all owned branches, worktrees, services, containers,
  databases, temporary fixtures, and their cleanup status.

Use full Markdown links for every GitHub issue and PR reference in human-facing records
and reports. On resume, reconcile the record against GitHub and local state; resume the
original snapshot rather than taking a new one. Verify uncertain prior mutations before
retrying them, especially pushes, PR creation, and merges.

## Select the next ticket

Refresh dependency status at the start and after each merge. Among tickets whose
prerequisites are satisfied, choose by these criteria, in order:

1. Explicit priority, following the repository's priority convention.
2. Number of remaining batch tickets the ticket would unlock, including downstream
   dependents; count each reachable ticket once.
3. Oldest creation time, then issue ID for a stable tie-break.

Record unavailable access, unresolved product decisions, dependency cycles, and unmet
out-of-batch prerequisites as blockers. Continue with independent tickets. Do not invent
requirements or grow the batch to solve a blocker. Revisit blockers when their relevant
conditions change. An issue being closed is not, by itself, evidence that its required
prerequisite behavior shipped.

## Complete one ticket

Exactly one ticket may be active. Only the required read-only Standards and Spec review
agents may run concurrently; delegate no implementation, validation, or queue management.
Finish validation, reviews, merge, and safe cleanup before starting another ticket.
If blocked, stop its activity and reviewers, preserve its work, and record retained
resources before moving to an independent ticket.

1. Fetch current remote `main` and create a uniquely named feature branch and owned
   worktree from that commit. Work only there. Never repurpose another task's branch,
   worktree, mutable fixtures, database, or infrastructure. Allocate task-owned test
   resources with unique names and explicit ownership; record them before use.
2. Follow the implement skill and acceptance criteria. Apply TDD at the recorded public
   seams: one failing behavior test, minimal implementation, then the next slice.
   Run focused tests and typechecking regularly; run the full required suite at the end.
   Follow repository-specific validation requirements.
   For documentation-only changes with no executable behavior, omit artificial TDD tests
   and run applicable documentation, link, formatting, and repository-required checks;
   record why the exception applies. Mixed changes still require behavioral validation.
3. Commit on the owned feature branch with hooks enabled. Pin the current main base SHA
   and candidate head SHA. Use the code-review skill to delegate independent read-only
   Standards and Spec reviews of that exact diff. Supply the standards, specifications,
   parent/dependency context, acceptance criteria, and validation evidence. Reviewers must
   not edit files, allocate infrastructure, or mutate shared resources. Both axes are
   required; missing specifications block the ticket rather than allowing Spec to skip.
4. Resolve all findings, including reasoned dispositions of inapplicable findings.
   Commit fixes and rerun affected validation and both reviews on the resulting head.
   Record each axis separately. Proceed only with no unresolved findings and a recorded
   reviewed head matching the candidate commit.
5. Push normally and open a PR describing the final behavior and validation, linking the
   ticket. If an owned PR already exists, update it. Wait for required checks and required
   reviews/merge requirements to pass for the reviewed head. Failed checks require repair
   and renewed validation/review; unavailable access or external approvals are blockers.
6. Immediately before merging, refresh remote main and verify the PR head still equals
   the reviewed SHA. If main advanced, merge current main into the owned branch normally,
   resolve conflicts, rerun affected validation and required checks, and repeat both
   reviews before merging. Push updates normally. If the head changed unexpectedly,
   inspect and revalidate ownership and review coverage before proceeding.
7. Squash-merge only the reviewed head, using a head-match guard where available (GitHub:
   `gh pr merge <pr-url> --squash --match-head-commit <reviewed-sha>`). Never force-push,
   bypass hooks or required checks, use an administrative bypass, or merge an unreviewed
   commit. Verify actual merge state and merge commit before marking the ticket merged.
8. Stop and remove only this ticket's owned disposable resources. Remove its worktree
   only when clean and confirmed merged. Delete its remote and local branches only after
   verifying their tips correspond to the merged PR; squash merges need PR evidence rather
   than ancestry alone. Preserve any unpublished changes or unexpected commits. Restore
   the task's intended checkout to main when safe; fast-forward a clean main without
   disturbing another task's checkout. Verify status and worktree inventory against the
   original inventory and record any retained resources.
9. Update the record, refresh dependencies, and select the next ticket automatically.

## Finish

Continue until every initial ticket is merged or no remaining ticket can proceed safely.
Do not stop after one ticket or ask whether to continue. If initial tickets were completed
externally, verify and record that outcome explicitly.

Report merged PR links, blocked or otherwise unmerged ticket links with reasons, retained
resources, and the progress-record path. Claim the batch complete only when every initial
ticket has a verified merged outcome; blocked tickets mean the batch remains incomplete.

Use `update_goal` with `complete` only after all initial tickets have verified merged
outcomes and required cleanup is done or retained resources are explicitly accounted for.
If no ticket can proceed, keep the record intact and follow the goal tool's blocking
threshold: mark `blocked` only after the same batch-wide blocking condition recurs for
at least three consecutive goal turns with no meaningful independent work available.
Reset that count when progress becomes possible or the user resumes a blocked goal.
Do not busy-poll unchanged blockers, pause without a user request, or mark blocked work
complete. On completion of a budgeted goal, report final token usage from the tool result.
