# Ask User

A Pi extension that adds an `ask_user` tool for presenting a choice to the
user. The agent receives the selected option and can continue with an explicit
human decision instead of guessing.

## Features

- Presents a question with at least two selectable options.
- Returns the selected option to the agent.
- Reports cancellation without pretending a choice was made.
- Fails clearly when used without an interactive UI.
- Runs sequentially so multiple prompts cannot overlap.

## Tool API

```json
{
  "question": "Which approach should I use?",
  "options": ["Option A", "Option B"]
}
```

The tool is named `ask_user` and is exposed to the model with prompt guidance
to use it whenever multiple valid choices require the user's decision.

## Structure

```text
ask-user/
├── README.md   # Documentation
└── index.ts    # Pi extension entry point
```

## Installation

This extension is managed by dotfiles-arch and synced to
`~/.pi/agent/extensions/ask-user`. Run `scripts/sync-extensions.sh` (or
`dfa-sync-extensions`) after changing it, then run `/reload` in an existing Pi
session.

## Conventions

The extension follows Pi's directory extension convention: `index.ts` exports a
default factory receiving `ExtensionAPI`, tool parameters use a TypeBox schema,
and the exported `AskUserInput` type mirrors that schema for TypeScript users.
The implementation only uses Pi's public extension API and keeps all user
interaction inside the tool execution context.
