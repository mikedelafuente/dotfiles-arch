---
name: advising
description: Advise the user through a plan or design with council-backed answers. Use for advise-me, advise-with-docs, or a request for a council-backed interview.
---

# Advising

Load [grilling](../../mattpocock/productivity/grilling/SKILL.md) once for its design tree, frontier, numbered
question format, and wait-for-human loop. Run one interview. This skill replaces
grilling's single-agent assessments with council recommendations; its council
workers are the only delegation needed.

Before recommending answers for each round, load the installed `agent-council`
skill once (Skill tool, or [sibling skill](../agent-council/SKILL.md)). Evaluate
the whole current frontier in one bounded run using its relevant-role selection
and Simple/Disputed routes. Put concrete council proposals in the `➡️` answers.
Reuse the assessment when the frontier's evidence and constraints are unchanged.
Loading integration instructions starts neither another interview nor another
council. If the council is unavailable, disclose that and continue with your own
recommendations.

Keep rounds focused on questions, recommendations, and material evidence,
assumptions, or dissent. Maintain the council's decision record across rounds,
including actual human answers; deliver its summary and detailed record when the
interview ends or pauses. A new frontier gets a new budget; an unresolved frontier
retains its exhausted budget until new user evidence arrives. Exhaustion pauses
with unanswered choices intact.

The user answers each question and confirms shared understanding before action.
For `/advise-with-docs`, use the loaded `domain-modeling` skill to record resolved
terms and accepted decisions in established glossary/ADR locations. Proposals
remain in the council record until accepted; offer ADRs under that skill's criteria.
