# Personal Cursor rules

Personal Cursor rules, tracked here so they follow you across machines. Unrelated to
`.cursor/rules/` at the repo root, which documents conventions for working **on this
dotfiles-arch repo** and is never touched by this sync.

Each file is a rule with YAML frontmatter + markdown body (see the
[Cursor rules docs](https://cursor.com/docs/context/rules)), as either a ready-made
`.mdc` file or plain `.md` — `.md` is auto-converted to `.mdc` on sync, so either works:

```
rules/
├── some-rule.mdc
└── another-rule.md
```

Frontmatter fields: `description`, optional `globs` (comma-separated glob string),
`alwaysApply: true|false`. A `README.md` here is never treated as a rule.

`scripts/sync-rules.sh` (run automatically by `dfa-sync-dotfiles`/`bootstrap.sh`, and daily
via `dfa-morning`) builds a normalized copy of each source's rules into
`~/.config/dotfiles-arch/rules-build/<slug>/`, then symlinks each `.mdc` from there into
`~/.cursor/rules/<name>.mdc`. Rules marked `alwaysApply: true` are also concatenated (body
only) into a per-source file symlinked to `~/.claude/dfa-rules-<slug>.md`, with a matching
`@dfa-rules-<slug>.md` import line appended once to `~/.claude/CLAUDE.md` — so Claude Code
gets the same always-on rules Cursor does. Any pre-existing real (non-symlinked) file at a
target name is deleted and replaced by the symlink. Everything managed here is removed again
once its source rule/import disappears. dotfiles-arch is always synced first; register extra
repos with `dfa-sync-sources add /path/to/repo` (later sources override on name collision).

Run it manually with `dfa-sync-rules`.
