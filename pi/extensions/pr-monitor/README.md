# PR Monitor

A Pi extension that adds `monitor_pr`, a long-running tool for watching a
GitHub pull request until it reaches a terminal outcome.

## Behavior

The tool polls `gh` and reports progress after each poll. It succeeds when the
PR has a `mergedAt` timestamp. It returns an error when:

- a check fails, is cancelled, or times out;
- the PR closes without merging;
- the PR has merge conflicts;
- the configured monitoring timeout expires; or
- monitoring is cancelled with `Ctrl+C`.

Pending checks and temporary merge states such as `BLOCKED` or `BEHIND` remain
monitorable rather than being treated as failures.

## Tool API

```json
{
  "pr": "92",
  "repo": "mikedelafuente/dotfiles-arch",
  "pollIntervalSeconds": 30,
  "timeoutMinutes": 30
}
```

- `pr` — required pull request number or URL.
- `repo` — optional `OWNER/REPO`; defaults to the current repository used by
  `gh`.
- `pollIntervalSeconds` — optional polling interval, minimum 5 seconds.
- `timeoutMinutes` — optional maximum wait, minimum 1 minute.

The tool requires the authenticated GitHub CLI (`gh`) and access to the
repository. It uses `gh pr view` and `gh pr checks`; it does not mutate the PR.

## Structure

```text
pr-monitor/
├── README.md   # Documentation
└── index.ts    # Pi extension entry point
```

## Installation

This extension is managed by dotfiles-arch and synced to
`~/.pi/agent/extensions/pr-monitor`. Run `scripts/sync-extensions.sh` (or
`dfa-sync-extensions`) after changing it, then run `/reload` in an existing Pi
session.

## Conventions

The extension follows Pi's directory extension convention: `index.ts` exports a
default factory receiving `ExtensionAPI`, parameters use a TypeBox schema, and
`MonitorPrInput` is exported for TypeScript consumers. Polling honors Pi's
abort signal and emits intermediate results through `onUpdate`.
