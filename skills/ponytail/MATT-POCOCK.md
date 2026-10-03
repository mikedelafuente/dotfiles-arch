# Ponytail inside Matt Pocock workflows

Use the local skills by name through the harness's skill tool. If there is no
skill tool, read the linked `SKILL.md` and follow it in the current workflow.
Resolve links relative to this file; no upstream checkout or plugin is needed.

The user controls activation and intensity. Keep their selected level, default
to full when none is selected, and skip these calls if they have turned Ponytail
off. Pass that preference and this file's path to delegated agents; they must
load the relevant skill themselves rather than assume they inherit its context.

## Planning and implementation

After understanding the task and existing code, invoke
[ponytail](SKILL.md) before choosing a solution or writing implementation.
Reuse existing code, stdlib, and native features before adding abstractions or
dependencies. Load it once per agent context, rather than every TDD slice.

The calling Matt Pocock workflow owns scope, completion, and output. Keep its
required reports, decision checkpoints, agreed test seams, red-before-green
cycles, regression coverage, and repository checks. Ponytail's one-check minimum
does not replace those tests. Simplify the implementation while satisfying every
accepted requirement; preserve security, accessibility, data integrity, and
load-bearing module interfaces. A runnable prototype can supply its own check.

If implementation introduces or changes `ponytail:` shortcut comments, invoke
[ponytail-debt](../ponytail-debt/SKILL.md) before reporting completion. Report the
relevant ceilings and upgrade triggers in the workflow's existing completion
report; save a separate ledger only when requested.

## Diff review

Invoke [ponytail-review](../ponytail-review/SKILL.md) on the calling review's same
pinned diff. In `code-review`, the Standards agent does this alongside its smell
baseline. Deduplicate overlapping findings and label complexity suggestions as
judgement calls. Respect documented standards and accepted requirements; retain
necessary tests. Keep the independent Spec review and both required reports.
The nested skill's one-shot ending ends that pass, not the parent workflow.

## Architecture survey

Invoke [ponytail-audit](../ponytail-audit/SKILL.md) within the survey's selected
scope. Compare deletion, reuse, and stdlib/native replacements with deepening
candidates before recommending a new interface. Carry useful findings into the
existing architecture report. Audit findings authorize no edits; the user still
selects the candidate to explore.
