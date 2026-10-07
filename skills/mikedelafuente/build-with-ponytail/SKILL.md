---
name: build-with-ponytail
description: Implement requested work using Ponytail guidance and the personal combined final review. Use when the user requests the combined implementation workflow.
---

Load installed Ponytail, or read [Ponytail](../../ponytail/ponytail/SKILL.md),
and apply its ladder at the user's selected intensity. Follow the implementation
workflow requested by the user, including its required checks and decision gates.
Use the current [implement](../../mattpocock/engineering/implement/SKILL.md) skill when no
more specific workflow was selected. Scope and authorization come from the user.

This wrapper owns final review: at the selected workflow's final code-review step,
use [review-changes](../review-changes/SKILL.md) once on all completed changes,
passing the fixed comparison point, spec, scope, and Ponytail preference. Finish
planned checks and coverage inspection first. Reuse the result for implementers;
review agents return findings without starting another coordinator. Fix confirmed
findings and ask only the responsible reviewer to verify affected paths.
Keep all other selected-workflow duties within the user's authorized scope.
