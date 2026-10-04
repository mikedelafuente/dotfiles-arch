---
name: adversarial-code-review
description: Thorough adversarial review of correctness, signatures, architecture, API contracts, project standards, tests, and control-flow complexity. Use for adversarial branch reviews or explicit codebase audits, and as the review engine called by code-review. Ordinary implementation does not trigger a repository-wide audit.
---

# Adversarial code review

Review along Matt Pocock's two independent axes:

- **Standards:** does the code follow the repository's documented coding standards?
- **Spec:** does it faithfully implement the originating issue or specification?

Adversarial inspection and Ponytail's complexity pass strengthen these axes.
Standards compliance cannot mask incorrect implementation of the spec, and spec
compliance cannot mask broken conventions. Prioritize correctness, clarity,
simplicity, language idioms, and consistency, in that order. Inspect implementation
bodies, tests, and actual callers; documentation, metrics, and prior audit checkmarks guide inspection but
do not establish compliance. Preserve product and security invariants.

Remain read-only unless fixes are requested. Review authorization permits no
implementation changes, database deletion, commits, or publishing.

## Establish scope and baseline

Resolve project references from the repository root. Read root and applicable
nested `AGENTS.md`, then discover governing standards from the repository:
contributor guides, domain/glossary documents, architecture and API policies,
ADRs, language/runtime guidance, testing instructions, and governing configuration.
Follow their references when applicable. Use documented precedence; distinguish
mandatory rules, contextual recommendations, exceptions, and unresolved conflicts.
Existing code demonstrates a convention, not necessarily a good one.

Discover release and compatibility requirements. Do not assume the project is
unreleased or its data disposable. Even an explicitly prelaunch project may have
required stable contracts. Recommend coordinated consumer updates rather than
shims only when the documented lifecycle permits that change.

Honor the requested scope:

- **Branch or working-change review:** use the fixed point the user supplied
  (commit, branch, tag, or merge-base); ask for it if absent. Confirm it resolves
  with `git rev-parse`, resolve it to a commit, and pin its merge-base with `HEAD`.
  Capture `git diff <fixed-point>...HEAD` and the commit list from
  `git log <fixed-point>..HEAD --oneline`, preserving Matt's three-dot semantics.
  Include scoped committed, staged, unstaged, and relevant untracked changes.
  Inventory with `git status --short`, committed changes from the base to `HEAD`,
  and index/working-tree diffs. Inspect both paths of renames and relevant deleted
  code. Read untracked files explicitly; ordinary diffs omit them. Stop before
  delegation if the ref is invalid or the combined scoped inventory is empty;
  working changes alone are reviewable. Share the pinned commands, commit list,
  content identities, and inventory with both reviewers.
- **Explicit codebase audit:** inventory the requested areas, or the whole
  repository if no narrower scope was given: production code, tests, data/schema,
  configuration, scripts, and consumers. Distinguish generated/vendor code from
  handwritten code and record exclusions. Inventory functions/methods, signatures,
  contract fields, operations/routes, and implemented architecture boundaries.

Trace surrounding consumers when needed to understand scoped behavior. Keep wider
recommendations separate; a diff review never silently becomes a whole-repo audit.
Record the checkout identity and reviewed working/untracked content. Before
completion, check for changes and reassess affected findings and coverage.

Build a coverage matrix linking each area to files/operations, applicable rules,
reviewer, and evidence. Give every applicable mandatory rule a disposition:
compliant with evidence, violation, documented exception, or unverified. Explain
inapplicable criteria and declined material recommendations. Include workflow and
validation requirements; passing tooling alone does not establish semantic compliance.
Preparation is complete when scope, baseline where applicable, inventory, governing
references, and compatibility assumptions are explicit.

## Find the originating spec

Use the target repository's `docs/agents/issue-tracker.md` or equivalent configured
tracker guidance. If no tracker guidance is present, tell the user to run
`/setup-matt-pocock-skills` to configure Matt's workflows; continue examining supplied
and local references while that setup is unavailable.

Look for the spec in this order:

1. Issue references in the scoped commit messages, retrieved through the tracker
   guidance. Branch metadata can supply additional originating-issue evidence.
2. A spec path or reference supplied by the user.
3. Matching files under `docs/`, `specs/`, or `.scratch/`, using the branch or feature.
4. Ask the user where the spec is if none is found; standards discovery can continue
   while waiting.

If the user confirms there is no spec, report **Spec conformance: skipped — no spec
available**. Do not invent requirements or count observed behavior as specification
compliance. The independent Spec reviewer still performs the added adversarial
correctness checks against domain documentation and consumers, reporting those
separately from spec-conformance findings. Unanswered or inaccessible spec requests
remain unverified, rather than being treated as confirmation that no spec exists.

## Apply the Standards baseline

Discover documented coding standards such as `CODING_STANDARDS.md`, `CONTRIBUTING.md`,
and the governing references above. The Standards axis always reads
[the full Fowler smell baseline](FOWLER-SMELLS.md), including direct invocations of
this skill without the `code-review` adapter. Give its resolved path or full contents
to the Standards reviewer, alongside the discovered standards sources.

Documented repository standards override smell heuristics. Label baseline smells
as judgement calls and cite the relevant hunk; cite the file and rule for documented
standard breaches. Skip duplicate mechanical checks enforced by tooling, while
retaining semantic review and recording tool-backed coverage evidence.

## Delegate independent reviews

For implementation workflows, start review after all planned code and test changes
are complete and required validation has finished. Finish coverage inspection and
any resulting test additions before delegation. Explicit review requests may still
review work in progress.

This skill owns the single Standards/Spec pair, whether invoked directly or
through another workflow. Run that pair once per parent task; an integration
workflow owns the pair for its implementers. Reuse completed results when another
skill reaches this coordinator in the same task. A new explicit user review request
starts a new review. An agent given a reviewer role executes only that role
and returns to its coordinator; it creates no additional pair and invokes no
review coordinator. Pass this role boundary to both agents.

Launch two read-only subagents in parallel. Give both the same scope, baseline,
inventory, user instructions, this skill and [review criteria](REVIEW-CRITERIA.md),
reference-reading duties, the current Ponytail preference, and discovered
spec/domain documentation. Include the full diff commands and commit list, standards
source paths, and the Fowler baseline path or contents in the Standards prompt;
include the spec path or fetched contents in the Spec prompt:

- **Standards:** assess clarity, idiomatic use of the project's languages,
  consistency, each scoped signature and parameter, architecture and dependencies,
  test quality, and complexity. Own the project-rule coverage matrix and contract
  style checks. Cite local rules and distinguish requirements from recommendations.
  Apply every Fowler baseline smell as a judgement call. When Ponytail
  is enabled (the default unless the user turned it off), invoke the leaf
  [ponytail-review](../ponytail-review/SKILL.md) on the same pinned changes, or
  [ponytail-audit](../ponytail-audit/SKILL.md) for an explicit codebase audit.
  Use the harness's skill tool or read the linked skill and follow it. Deduplicate
  complexity findings with other smells, keeping them optional unless they violate
  a governing requirement. Repository rules, accepted requirements, security, and
  necessary tests take precedence over simplification suggestions. Return findings
  to this coordinator after the leaf pass; its one-shot ending ends only that pass.
- **Spec:** explicitly check (a) missing or partially implemented requirements,
  (b) behavior not requested by the spec (scope creep), and (c) requirements that
  appear implemented but behave incorrectly. Quote the supporting spec passage
  for each conformance finding. Independently trace intended behavior against
  domain documentation and actual consumers. Assess invariants, authorization,
  isolation, transactions, retries, failures, and observable contracts where present.
  Check whether proposed signature/architecture simplifications preserve behavior.
  When spec conformance is skipped or unverified, label that disposition and
  keep the added correctness findings separate from conformance claims.

Keep initial conclusions independent. Each reviewer reports assessed areas,
evidence-backed findings, and uncertainties. Keep each findings narrative under
400 words; put detailed coverage and evidence in a separate structured return to
the coordinator rather than dropping findings to meet that narrative limit. Wait
for both, investigate disagreements, and reconcile coverage. If delegation is unavailable, disclose that the independent
review gate is unmet and label any assessment partial.

## Inspect and require evidence

Read [review criteria](REVIEW-CRITERIA.md) before reviewing. Trace representative
operations from entry point through business logic and side effects, including
failure paths. Sampling helps trace behavior but does not replace assessment of
every operation, signature, boundary, or route in the declared inventory.

Every finding needs:

1. Exact file and line, or the nearest relevant location for an omission.
2. Problematic behavior or a specific comprehension cost.
3. A reproducible scenario or concrete code evidence; label inference/uncertainty.
4. Applicable local rule and section, or a design-recommendation label.
5. The smallest coherent correction, accounting for affected callers.
6. Behavior to preserve and validation needed to prove the correction.

Separate correctness/security defects, required-rule violations, and optional
improvements. Rank by impact and deduplicate within each axis without losing
evidence or reviewer attribution. Cross-reference overlap between axes while
preserving separate findings and counts. Ground consistency claims in compared
examples. Personal preference, arbitrary complexity thresholds, and function-length
limits are not defects.
Findings need no minimum count. Read-only checks must not alter the checkout or
external state; report needed tests or destructive checks as unrun.

## Report and complete

Present the two reports under `## Standards` and `## Spec`, verbatim or lightly
cleaned. Preserve each axis's findings, attribution, and count. Do not merge or
rerank findings across axes or choose a single worst issue across both; the axes
are deliberately separate. Investigate disagreements and cross-reference overlap
without letting one axis's result hide the other's.

Include a short remediation plan within each axis, assessed scope, coverage matrix,
applicable API dispositions, complexity hot spots, and unresolved uncertainties.
Keep large inventories in a supporting artifact only when the user requests one.
Distinguish inspected, tested, skipped, and unverified conclusions; identify remaining
files, operations, rules, and paths. A clean scoped review means no supported
findings in the assessed scope, not proof of absence. Skipped spec conformance is
not a Spec pass.

End with one line containing the finding count and worst issue **within each axis**,
or its skipped/unverified disposition. Honor a user-supplied report format while
retaining the separate axis results.

An audit is complete only when every declared area, signature, boundary, operation,
and applicable rule is assessed and both independent results are reconciled.
Resource limits or missing evidence mean a partial audit with an explicit remaining
inventory, not a clean bill of health.

When fixes are authorized, follow the target project's testing and validation
requirements and update callers/tests/contracts/docs coherently. Batch fixes and
rerun the affected checks before asking the existing responsible reviewer to verify
only unresolved findings and their affected callers. Keep the other axis's completed
result. Once findings are resolved, finish the task; passing checks, added tests,
commits, and PR preparation do not trigger another full review pair. Honor documented
exceptions, including documentation-only checks. Fix
authorization alone does not authorize committing or publishing.
