---
name: infer-once
description: "Turns a solved, repeatable LLM task into a reusable script, tool, or template so future runs need zero (or far less) inference. Use when a task will recur (data transforms, table/scaffold generation, migrations, boilerplate, report generation, CI steps, repeated code-review checks), when the user asks to automate/speed up/reduce the cost of something they keep asking for, or when the user mentions token burn, cost optimization, or 'do this every time'. Also self-apply: if you notice you're about to redo the same multi-step manual work a third time, stop and export it first."
license: MIT
---

# Infer Once

Kelsey Hightower's "zero token architecture," compressed to one line: **infer once, export the result, run it again without inference.** Not a tech, a discipline — the same reason caches, compiled binaries, and libraries exist. You don't pay a developer to hand-write a SQL driver on every query; don't pay an LLM to re-derive a solved procedure on every run either.

## The core loop

1. **Do the work once, with full reasoning.** Use inference to explore, make mistakes, and converge on the *correct* approach. Don't skip this — you can't export what you haven't understood.
2. **Export it as a durable artifact**, not a one-off answer: a script, CLI tool, function, template, Makefile/CI target, or config generator. Something that runs on a plain interpreter/CPU with no model call.
3. **Re-run the artifact, not the prompt**, for every future instance of the same task.
4. **Only re-invoke inference when the underlying requirement changes** — new shape of input, new rule, new edge case. Then you update the artifact once, and it's cheap again forever.

If a task will only ever happen once, this loop doesn't pay for itself — just answer it. The trigger is repetition, not "could this be a script."

## Recognizing the signal

Ask this before doing the work, not after the third time you've done it:

- **Will this exact kind of request come up again?** (another table, another endpoint, another report, another environment)
- **Is the procedure actually deterministic** once the approach is decided — same inputs, same steps, same output shape?
- **Am I about to hand-walk a multi-step sequence I've already walked before** in this session or a recent one?
- **Did the user say "every time," "again," "from now on," "automate," "make this faster/cheaper," or mention token cost?**

Any "yes" is the moment to propose exporting — before grinding through the Nth manual pass.

## What "export" looks like

Match the artifact to the task, in order of preference:

| Task shape | Export as |
|---|---|
| Repeated data transform / migration | A script (Python/bash/etc.) that takes the same inputs and produces the same outputs deterministically |
| Repeated scaffold (table, module, test file, boilerplate) | A generator script or template the user (or you) invokes directly next time |
| Repeated review/lint check | A static rule (linter config, SonarQube rule, grep/AST check) instead of an inference pass every PR |
| Repeated CI/deploy step | A pipeline step or Makefile target, not an agent loop re-deciding the steps each run |
| Repeated multi-file edit pattern | A codemod or find/replace script, not a fresh multi-tool-call edit sequence each time |

Prefer the plainest tool that does the job (a shell script beats a Python package beats a "framework"). The goal is something a CPU runs for pennies, not something that re-derives the plan.

## Doing this well vs. cargo-culting

The talk's warning applies to you too: exporting a script you don't understand just relocates the problem. Before exporting:

- Make sure *you* (not just "the model") can explain why the script does what it does — you may need to modify it later without inference.
- Don't wrap the export in unnecessary flexibility "for the future" — export what today's repeated case actually needs (see repo-wide anti-over-engineering guidance).
- If the user can't maintain the artifact once it's handed over, that's a signal to keep it simple and documented, not to add more agent scaffolding around it.

## Anti-pattern: burning tokens to save tokens

Don't respond to "this costs too much" by building an agent that manages/monitors/optimizes the inference loop. That's more inference spent guarding inference. The fix is almost always: stop calling the model for this at all, run a script instead.

## Applying this in a coding session

When you notice the signal above, say so and propose the export explicitly, e.g.:

> "You'll likely need this again — want me to turn this into a script/generator you can re-run directly instead of asking me each time?"

Then:
1. Finish the current instance using normal reasoning.
2. Write the script/tool capturing exactly what you just did (parameterized on whatever varies between instances).
3. Verify the script reproduces the just-completed result.
4. Tell the user how to invoke it next time without you.

Don't silently export everything — routine one-shot edits and exploratory questions don't need this ceremony. Reserve it for genuinely recurring, deterministic work.
