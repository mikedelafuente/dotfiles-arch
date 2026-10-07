---
name: infer-once
description: "Export recurring LLM work as scripts, tools, or templates so future runs need zero inference. Use when the same task will recur (transforms, scaffolds, migrations, boilerplate, reports, CI steps, repeated review checks), when the user asks to automate something or mentions token cost, or self-apply when you are about to hand-walk the same multi-step sequence a third time."
license: MIT
---

# Infer Once

**Infer once, export, re-run without inference.** Same discipline as caches and compiled binaries: pay the reasoning cost once, then let a CPU run the artifact.

One-shot and exploratory work stays inline — the trigger is **repetition**, not "could this be a script."

## Signal check

Run this **before** the work, not after the third manual pass:

- **Recurrence** — will this exact kind of request come up again? (another table, endpoint, report, environment)
- **Determinism** — once the approach is decided, are inputs → steps → output shape fixed?
- **Déjà vu** — are you about to hand-walk a multi-step sequence you already walked this session or recently?
- **User intent** — did they say "every time," "automate," "from now on," or mention cost/tokens?

Any **yes** → run the steps below. All **no** → answer normally; one-shot edits and exploration need no ceremony.

## Steps

1. **Propose the export.** Stop before the Nth manual pass. Say explicitly, e.g.:
   > "You'll likely need this again — want me to turn this into a script you can re-run without me?"
   **Done when:** user has said yes, or you have a clear implicit mandate ("automate this," "every time").
2. **Finish this instance with full reasoning.** Explore, converge on the correct approach. You cannot export what you have not understood.
   **Done when:** today's task is complete and you can explain why the approach works.
3. **Write the artifact.** Capture exactly what you did — script, CLI, template, Makefile/CI target, linter rule, or codemod. Parameterize **only** what varies between instances; export today's case, not a hypothetical future.
   **Done when:** a plain interpreter/CPU can run it with no model call.
4. **Verify.** Run the artifact on the same inputs you just used; output must match what you produced manually — zero meaningful differences.
   **Done when:** verify command passes; if it fails, fix the artifact before handoff.
5. **Hand off.** Give one command, one example input, and the expected output shape so the user can re-run without you.
   **Done when:** invocation needs no agent in the loop.

## Export kinds

Match artifact to task; prefer the plainest tool (shell script → single script → package — never a framework):

| Task shape | Export as |
|---|---|
| Data transform / migration | Deterministic script (Python, bash, …) |
| Scaffold (table, module, test, boilerplate) | Generator or template invoked directly |
| Review / lint check | Static rule (linter, SonarQube, grep/AST) — not an inference pass per PR |
| CI / deploy step | Pipeline step or Makefile target |
| Multi-file edit pattern | Codemod or find/replace script |

## Reference

### Core loop

1. Infer once with full reasoning.
2. **Export** a durable artifact.
3. Re-run the artifact, not the prompt.
4. Re-infer only when requirements change — new input shape, rule, or edge case — then update the artifact once.

### Export well

- You (not just the model) can explain why the script does what it does — you may edit it later without inference.
- Parameterize only what actually varied today.
- If the user cannot maintain the artifact, keep it simpler and document the invocation — do not wrap it in agent scaffolding.

### Meta-agents

When cost is the complaint, the fix is a **plain script**, not an agent that monitors or optimizes inference. More inference guarding inference rarely pays.
