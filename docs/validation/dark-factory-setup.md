# Factory setup validation — revision 4

Date: 2026-10-09. Base: `4d6cefb7081d4d78e118b0429ea5c0dda2b10c45`.

- `dfa-deploy source` verified this actual source checkout before edits.
- `AGENTS.md` resolves to project-local `CLAUDE.md`; existing content was
  preserved and one marked loading block appended.
- Required setup fields, schema/revision/status, finite proposed limits, effort
  mapping, charter references and acceptance separation passed local assertions.
- All setup and project-evidence file references passed the existing control
  module's `reference` SHA-256/root/regular-file validation. Installed skill
  discovery identities also matched their recorded hashes.
- Control CLI `init` against the setup index in a temporary private store returned
  exit 1, `status: parked`, `reason: missing run`, as required. No bundle/state was
  admitted. The CLI has no standalone semantic setup-validation command; its
  full executable bundle check awaits actual receipts, selected graph, criteria,
  pinned private artifacts and a finite absolute deadline.
- `python3 tests/test_dark_factory.py` passed existing supplied-fact checks for
  approval, claims, budgets, independent acceptance, trial pauses, resume/fencing,
  record drift, graphs, context packets and retro publication guards.
- `git diff --check` passed.

These checks establish proposal/reference integrity and control-seam behavior.
They do not establish runtime runner/tracker/verifier adapters, hard budget
termination, worker isolation, actual launch settings, scheduling or workstation
behavior. No build, tracker publication, deployment or schedule was performed.

Revision 2 connects environment inspiration from factory planning guidance,
keeps source examples optional for vague goals, and pins the research note in
the setup evidence. Updated references and the relative loading link were checked.

Revision 3 records the human request for observe-only calibration and usage reports.
Token/time caps are explicitly null across run/task/wake policies; other guards
remain. Current control CLI finite-limit incompatibility is explicit and blocks
this execution mode until supported. Updated JSON/references and reporting fields
were checked; no unlimited runner or measured telemetry is claimed.

Revision 4 replaces the initial controller incompatibility with tested source
support for observe-only run/task/attempt/repair caps. The existing control test
now covers multi-million-token uncapped attempts, retry history/late settlement,
missing usage, fractional timing, per-item and project/model/effort reports,
receipt integrity, duplicate stores/callbacks and mixed explicitly capped units.
An independent supplied-fact forward check passed retry, evaluator accounting,
reports, project aggregation and actual trial transitions in a private /tmp store.
Skill YAML/frontmatter/name checks passed via Ruby Psych; the bundled validator
lacked PyYAML. Local Markdown references were checked. Installed skill adoption
and live runner usage remain separate from this source validation.
