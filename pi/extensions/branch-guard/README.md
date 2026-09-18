# Branch Guard

A Pi extension that protects the main line from agent file edits. Before the
first `edit` or `write` tool call on `main` or `master`, it moves the work onto
a feature branch.

## Behavior

- If no other local branches exist, creates a generated `work/<repo>-<timestamp>`
  branch automatically.
- If other local branches exist, asks whether to switch to one or create a new
  branch.
- Prompts for the name when creating a branch from the selection menu.
- Blocks the file edit if branch selection, branch creation, or branch switching
  fails.
- Leaves detached HEADs and non-main branches unchanged.
- Does not stash or discard existing changes; Git's normal switch safety checks
  still apply.
- Blocks edits in non-interactive modes because it cannot safely ask which
  branch to use.

The guard applies to Pi's built-in `edit` and `write` tools. It does not try to
interpret arbitrary shell commands.

## Structure

```text
branch-guard/
├── README.md   # Documentation
└── index.ts    # Pi extension entry point
```

## Installation

This extension is managed by dotfiles-arch and synced to
`~/.pi/agent/extensions/branch-guard`. Run `scripts/sync-extensions.sh` (or
`dfa-sync-extensions`) after changing it, then run `/reload` in an existing Pi
session.

## Conventions

The extension follows Pi's directory extension convention: `index.ts` exports a
default factory receiving `ExtensionAPI` and uses the `tool_call` event to block
an edit before it executes. Branch operations use Git's CLI and the current
extension context directory.
