# Merge PR

Adds the `merge_this` tool for the full branch-to-PR workflow used when the
user asks to merge the current work.

## Workflow

1. Create a work branch if the current branch is `main` or `master`.
2. Stage and commit outstanding changes.
3. Push the branch and create or reuse its open PR.
4. Check PR state and checks through `gh` every 10 seconds.
5. Rebase the PR through `gh pr update-branch --rebase` when it is behind or
   conflicted, then wait for checks again.
6. Prefer a squash merge through `gh pr merge --squash`.
7. Confirm GitHub reports `mergedAt` before doing any cleanup.
8. Delete the remote branch through `gh api`, switch to `main`, pull the latest
   `main`, and delete the local branch.

The branch and local checkout are deliberately left untouched if the merge is
not confirmed. GitHub operations use the authenticated `gh` CLI; local branch
and commit operations use Git.

The workflow reuses the polling and check-classification helpers exported by
`pr-monitor`, so both tools use the same PR state model, failure detection, and
10-second GitHub polling interval.

## Tool API

```json
{
  "commitMessage": "feat: requested changes",
  "prTitle": "feat: requested changes",
  "prBody": "Summary and validation",
  "timeoutMinutes": 30
}
```

All fields are optional. The workflow checks GitHub at a fixed 10-second
interval and supports cancellation through Pi's abort signal.

## Structure

```text
merge-pr/
├── README.md   # Documentation
└── index.ts    # Pi extension entry point
```

## Installation

This extension is managed by dotfiles-arch and synced to
`~/.pi/agent/extensions/merge-pr`. Run `scripts/sync-extensions.sh` (or
`dfa-sync-extensions`) after changing it, then run `/reload` in an existing Pi
session.

## Safety

- Squash merge is attempted before any rebase fallback.
- No branch deletion or checkout occurs before GitHub confirms the PR merged.
- A failed check, closed unmerged PR, timeout, or failed merge leaves the
  current branch in place and returns the failure reason.
