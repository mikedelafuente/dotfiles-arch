---
description: Avoid setup-status messages
alwaysApply: true
---

Do not report skill-alias or sandbox diagnostics as progress.

- Resolve skill aliases from the session's `Skill roots` table immediately.
- If a skill path is unavailable, use the best fallback and state it only if it blocks the task.
- Treat GitHub/network access as approval-gated. Attempt the required `gh` command, request escalation if blocked, then continue.
- Never say “I’m resolving …” unless user action is actually required.
