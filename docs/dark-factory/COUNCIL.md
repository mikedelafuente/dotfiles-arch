# Project council — revision 1, proposed

Domain: personal/work GNOME development workstations on Arch and Ubuntu. Actors:
maintainer, workstation user, IT-managed enrollment owner, coordinator, implementer,
independent evaluator and human trial owner. Workflows: bootstrap, recurring sync,
updates, installed-generation deployment, source capture/override and recovery.

## Remits and evidence ownership

| Lens | Question / owned evidence | Initial recommendation |
|---|---|---|
| BA | What behavior helps the workstation user? Own workflow exceptions and measurable business acceptance from README, PACKAGES and deployment docs. | Require a concrete first goal; fixture success alone cannot prove workstation behavior. |
| PM | Which approved outcome earns the investment? Own scope, priorities and trial criteria. | One finite change per milestone; first priority remains unanswered. |
| TPM | Can tracker, runner and update/deployment boundaries interoperate? Own capability and API evidence. | Reuse documented sub-issues/dependencies; block execution until verifier, telemetry and fencing routes are proven. |
| SA | How are state, permissions and failure isolation preserved? Own architecture and ADR compatibility. | Retain modular scripts and one runner; private durable state outside worktrees, with separate acceptance and action authority. |
| SE | What existing code and checks cover the change? Own caller tracing and regression proof. | Reuse fn-lib/run-profile-setup/deployment seams and smallest relevant fixture checks. |

Setup uses all five **single-agent lenses**, one initial assessment per lens and
one cross-check. No independent council agents ran; no roles were omitted or timed
out. For future questions select only relevant remits and record omissions/missing
coverage. At most one initial and one challenge per selected remit, two focused
follow-ups total. Evidence resolves factual disputes; agreement/votes confer no
acceptance. Independent execution evaluators remain distinct from implementers.

## Cross-check and alternatives

Strongest alternative: retain interactive issue-by-issue delivery with no factory
state or supervisor. It costs less and remains usable while execution adapters are
missing. The proposed records make the desired bounded mode reviewable without
starting it. Milestones were chosen by the user; explicit issue sets and reuse of
the existing wayfinder map were alternatives. No conflicting evidence or retained
lens dissent was found; unsupported runner guarantees remain a material gap.

The council recommends setup acceptance only after the maintainer reviews the
pinned records. Direction, actions, spending and scheduling are separate gates.
See `decisions.json` for actual answers versus proposals and `coordination.json`
for capability gaps. Existing repo evidence is sufficient for these proposals;
only tracker integration documentation needed a scoped primary-source lookup.
No external reference architecture is adopted.
