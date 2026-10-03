---
name: code-review
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base) along two axes: Standards (does the code follow this repo's documented coding standards?) and Spec (does the code match what the originating issue/spec asked for?). Runs both reviews in parallel sub-agents and reports them side by side. Use when the user wants to review a branch, a PR, work-in-progress changes, or asks to \"review since X\"."
---

Invoke [adversarial-code-review](../adversarial-code-review/SKILL.md) using the
harness's skill tool, or read the linked skill and follow it when no tool exists.
Pass the user's comparison point, requested paths, spec references, report
preferences, and current Ponytail preference. That skill owns the full review
workflow, including Matt Pocock's Standards/Spec contract and Fowler smell baseline.
