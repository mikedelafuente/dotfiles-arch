# Agent council validation

Base: `6378e04bc16fbd94908e3c90a541cbab76f1052e` (`main` and fetched
`origin/main`). Built locally on `feat/agent-council` in an owned worktree.
This is an instruction-driven workflow using the harness's agent tools; it adds
no service, CLI, package, or external project dependency.

## Structural and distribution checks

- `bash scripts/check.sh`: PASS, `bash -n` on 86 files and `shellcheck -x`.
- `bash -n home/.bashrc`: PASS for the modified shell help function.
- `git diff --check`: PASS.
- Bundled `skill-creator/scripts/quick_validate.py`: could not run because the
  environment lacks PyYAML. No dependency was installed. This is a tooling
  limitation, not a passing result.
- Alternative check with installed Ruby Psych (`YAML.safe_load`): PASS for
  `agent-council`, `grilling`, `to-spec`, and `to-tickets`: frontmatter parsing,
  folder/name agreement, valid name/description lengths, unfinished placeholders,
  and all relative Markdown references. Non-empty council references also checked.
- Actual `sync_skills_from_repo` and `prune_managed_symlinks` helpers: PASS,
  two runs into isolated temporary Claude, Cursor, Codex, and Pi targets. Each
  target's council symlink resolved to this worktree; referenced record file was
  readable. No live harness files or source configuration were changed.

The local alternate structural check and isolated distribution runner are at
`/tmp/council-validation/structure.rb` and
`/tmp/council-validation/distribution.sh`; they are execution evidence, not
runtime dependencies. Normal skill distribution remains `dfa-sync-skills`.

## Independent review

Independent Standards and Spec reviewers read the complete working-change
inventory, including the untracked council files, against the fixed base and
originating task. Standards found one stale README claim about untouched vendored
skills; it was corrected to identify `grilling`, `to-spec`, and `to-tickets`
customizations. Spec found no static conformance defects. Fowler/Ponytail checks
found no supported complexity finding. These reviews establish inspected scope,
not proof of every future model run.

## Behavioral demonstrations

An independent evaluator read the actual skill and its references, then executed
three realistic requests in an isolated `/tmp/council-forward-test` workspace.
Evaluator and delegated roles were selected as `gpt-6.1-sol`, medium effort.
The cases below summarize observable outputs, not private reasoning.

### Simple CSV export

Input: read-only CSV, at most 200 rows, supplied measurement 100 ms, page
authorization, no scheduling requirement. The evaluator produced five single-agent
lenses and a strongest-alternative cross-check, spawning no roles. It recommended
synchronous export, with a representative slow-case check and authorization/row
bound review. Supplied measurements were labeled assertions, not independently
verified facts. The ledger retained “not answered” and **proposed** status;
implementation handoff remained conditional.

Human output: “Q1: Keep the export synchronous. The supplied measurement is
100 ms for up to 200 rows, and the existing page authorization applies. A
background job would add job tracking and result delivery without a stated
scheduling need.” The remaining summary exposed the measurement uncertainty,
validation, and unaccepted status.

### Neutral community booking idea

Input: 30 members, overlapping equipment bookings cause problems, one volunteer
maintainer; compare calendar and custom app. The evaluator chose disputed mode
for the outcome/ownership uncertainty, ran five isolated roles in batches of
three then two, then five cross-role replies. No lookup or focused revision
was needed. The initial BA position required calendar-level prevention, while
others favored a manual pilot. Concrete simultaneous-request and approval-load
counterexamples changed positions: preventing conflicting confirmed commitments
is the outcome; displaying availability alone does not establish prevention.

The final recommendation was a conditional calendar pilot with explicit
confirmation, measured conflict/delay/administration outcomes, and human-defined
limits. Immediate conflict-free self-service would require a verified enforcement
system and sustainable ownership. An existing maintained service was identified
as an unresearched alternative, not a product endorsement. An overly broad role
claim about automatic rejection was explicitly narrowed by the coordinator;
agreement did not erase it. No answer was attributed to the human, and no
accepted implementation scope or external permission was invented.

Human output: “Q1: Try a shared calendar only if members accept a clear
confirmation process and someone can run it reliably. A calendar that merely
shows availability still allows two people to book the same item.” The remaining
summary covered maintenance, pilot criteria, conditional alternatives, and human
choices. The detailed output separately retained all five initial positions,
claims, challenges, source IDs, revisions, and the actual unanswered Q1 ledger.

### Disputed grilling with docs

Input: volunteer scheduling service, low-cost priority, one operator, prospective
customer asks for undefined isolation, no contract, whole-database shared backups,
no tested customer-specific restore. Existing Q1 asks shared versus dedicated;
Q2 asks whether customer-specific restore should be promised. Actual human answer:
“I prefer shared if it is sufficient; I have not committed yet.”

The evaluator read `grilling` and `domain-modeling`, ran five independent initial
assessments and five cross-role replies (zero extra lookups/follow-ups), and kept
only unresolved Q1 in the frontier. Challenges corrected three overclaims:
shared's total cost advantage is unmeasured; absence of a contract does not prove
customer fit; dedicated databases on shared infrastructure do not establish
independent failure or recovery capabilities. All roles settled before debate.

The human's exact quote remained **proposed/unresolved**, never accepted. Q2
remained **deferred**, without an invented answer or restore promise. The human
output used the actual numbered grilling format:

> ❓ **Q1** - **Should we use shared or dedicated databases?**: What isolation
> boundary must the service satisfy, and will you choose shared if that boundary
> can be demonstrated within the volunteer's operating capacity?
>
> ➡️ Prefer shared provisionally, conditional on demonstrated customer separation
> and acceptable operating effort. Choose dedicated if an accepted isolation
> requirement cannot be met by shared and a specified dedicated design
> demonstrably meets it within the operating budget.

The final output explicitly waited for a human answer. No resolved terminology or
accepted decision existed, so it wrote no authoritative glossary/ADR. The detailed
agent record retained initial views, challenges/revisions, evidence IDs, actual
Q/A and deferred prerequisites. Implementation-ready spec/ticket handoff was
**blocked**, with conditional planning context only. No external authority or
shared-understanding confirmation was attributed to the council.

## Evidence and limits

Actual separate human/detail outputs for all cases are preserved at
`/tmp/council-forward-test/case{1,2,3}/{summary.md,agent-output.md}` on the build
host. These temporary files are supporting execution evidence, not part of the
installed skill. This report retains representative outcomes in the repository.
All three cases completed within the specified call budgets; no nested councils,
missing roles, automatic retries, live project edits, or external actions occurred.
The coordinator inspected the actual artifacts after execution.

The tests used supplied assertions, not a real service or measured operational
capabilities. Model selection was specified by the harness dispatch arguments;
case 1's internal record conservatively reports inherited settings as not exposed.
Timeout/delegation-failure paths were reviewed but not exercised. `/bro` and
tracker publishing were checked against their actual skill instructions, not
executed; no tool use or new evidence was falsely attributed to `/bro`.
A ready decision record does not prove correctness or authorize downstream action.

Final freshness check: fetched `origin/main` still resolves to
`6378e04bc16fbd94908e3c90a541cbab76f1052e`; original `main` checkout remained
clean. During the original build, no commit, push, PR, merge, dependency install,
or live skill sync occurred. A later explicitly authorized installation is
recorded below.


## Failure-path simulations and authorized local installation

Independent coordinator simulations injected three conditions rather than causing
real service failures: SA initial timeout after five dispatches; unavailable
delegation; and persistent BA/SA dissent after five initials, five replies, one
lookup and two revisions. Outputs are at
`/tmp/council-failure-simulation/case-{a,b,c}/{summary.md,agent-output.md}` with
accounting in `observations.md`. Timeout coverage was missing, never assent;
unavailable delegation used five disclosed single-agent lenses; exhausted debate
stopped with dissent and the unanswered disclosure choice intact. No new role
calls, retries, publication or invented human answers occurred. Full prior role
records were not supplied in these simulations; actual transport timeout,
cancellation and unavailable-provider behavior remain untested.

The user subsequently explicitly authorized local installation only. Stable
snapshot: `~/.local/share/dotfiles-arch/agent-council-local/skills/`, containing
`agent-council`, `grilling`, `to-spec`, and `to-tickets`, including their references
and existing licenses. No installed link points into the build worktree.

Registration used the existing script:
`bash scripts/sync-sources.sh add ~/.local/share/dotfiles-arch/agent-council-local`.
Applying only `sync_skills_from_repo <snapshot> standard <target>` preserved other
sources, unrelated skills, settings, bro and original grill wrappers; no global
prune or Pi settings migration was run. All 16 links and content readbacks passed:
`~/.claude/skills`, `~/.cursor/skills`, `~/.codex/skills`, `~/.pi/agent/skills`.
Codex was detected on PATH; no relocation environment variables were set here.
The protected Codex path required an authorized elevated symlink operation; no
credentials or permission settings changed.

Verification compared every unrelated skill entry's identity before/after and
used Pi's installed native `loadSkillsFromDir` to discover all four skills, with
no relevant diagnostics. Exact invocations: Codex `$agent-council <question>`;
Claude `/agent-council <question>`; Pi `/skill:agent-council <question>`; or ask a
supported agent to use agent-council. Pi's installed documentation confirms
`/reload`; other cached catalogs need a fresh session. The current executor
skill catalog remained cached and did not expose the new package; filesystem
installation and Pi loader discovery were verified, not a fresh live LLM session.

This registered snapshot overrides main for these four skills during future sync.
Retain it until the changes are approved and incorporated into main; its
`INSTALLATION.md` documents retirement and returning links to main. No commit,
push, merge, issue publication, extra package, or project implementation occurred.

## Grilling/advising split — 2026-10-03

The later split supersedes the grilling integration above. `grilling`, `grill-me`,
and `grill-with-docs` now use the coordinator's own recommendations. `advising` reuses
the interview contract and adds automatic council recommendations; `advise-me`
and `advise-with-docs` are its entrypoints. The docs variants retain domain-modeling
and record accepted decisions, while council proposals remain proposals.

Independent Standards and Spec reviewers inspected the changed skills, wrappers,
metadata, references, and user docs against `d2e07b9d11dc0ee22d880610e968c836688ae568`;
neither found actionable issues. Scenario inspection covered ordinary grilling,
new/unchanged frontiers, partial answers, budget exhaustion, docs acceptance,
and standalone council. These were semantic reviews, not live model runs.

Pi's installed native `loadSkillsFromDir` and `formatSkillsForPrompt`, plus its
existing YAML parser, validated all seven changed/new skills: discovery without
diagnostics, names, explicit wrapper policy, metadata, relative references, and
prompt inclusion. The bundled skill-creator validator could not run because
PyYAML was unavailable; native loader validation supplied the check without a
dependency install. `bash -n home/.bashrc` and `git diff --check` passed.

The registered stable snapshot was updated for these seven skills and linked
into Claude, Cursor, Codex, and Pi. All source files matched the repository;
discovery/policy/reference checks passed for the snapshot and all four installed
directories. Unrelated skill entry identities were unchanged, including to-spec
and to-tickets. A sibling `domain-modeling` symlink resolves docs references to
the primary repository; the sync helper's real-directory selection excludes it
from overrides. No installed link points into this worktree. Existing snapshot
files were backed up under `/tmp/advising-skills-backup-4y0icnr6`.

Fresh live model execution and token savings were not measured. Cached skill
catalogs require a new session, or `/reload` in Pi. No commit, push, merge, or
publication occurred.

Before merge, the original grilling wrappers and fact-finding delegation were
retained. The split removes council recommendations from grilling, while
discoverable facts can still be researched by a subagent. User docs reflect that
distinction; the initial local installation above describes the earlier snapshot.
