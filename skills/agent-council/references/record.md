# Council record contract

Produce two distinct outputs, in chat or as the requested files. Use the user's
language for the summary. Tables are optional when short prose is clearer.

## Human summary (`summary.md`)

In roughly 5–8 plain sentences, say what to choose and why, the biggest cost,
what is still uncertain, whether a meaningful dissent remains, and the next
human choice. Mark a conditional or blocked recommendation clearly. Preserve
question IDs so it can be matched to the detailed record. Do not hide a blocker
just to make the summary shorter.

## Detailed agent output (`agent-output.md`)

- **Brief:** exact user question(s), project/context, constraints/non-goals,
  chosen route, actual model/effort if known, delegation limitations and budget used.
- **Evidence:** stable IDs E1, E2, … with source path/section or URL, relevant
  fact, and freshness/contradiction notes. Label supplied assertions and assumptions.
- **Initial positions:** five attributed assessments, written before debate;
  answer, evidence IDs, alternative, assumption, risk, change condition, human choice.
- **Challenges:** contested claim, challenger/respondent, evidence/counterexample,
  retained/revised answer and concise reason. Include the strongest-alternative
  cross-check on the simple route. Record timeouts/missing roles as missing coverage.
- **Decision ledger:** Q ID and actual question; council recommendation; actual
  human answer verbatim when supplied (otherwise “not answered”); concise rationale;
  status; evidence; tradeoff; assumption; dissent; unresolved prerequisite/choice.
  In a multi-turn interview, append each actual answer/revision; keep superseded
  answers identifiable. Never fabricate answers or record private chain-of-thought.
- **Outcome:** recommendation or blocked/conditional result, rejected alternatives
  and why, unresolved material objections, smallest next validation, human choices.
- **Handoff:** accepted scope/non-goals, acceptance criteria, dependencies, open
  choices, evidence/record references; indicate ready, conditional draft, or blocked.
  A ready record is context for a later requested skill, not authority to publish.

A user explicitly deferring a material choice is still an unresolved prerequisite
for any dependent implementation; record the deferral rather than filling it in.
