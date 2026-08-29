# Personal Cursor rules

Personal Cursor rules, tracked here so they follow you across machines. Unrelated to
`.cursor/rules/` at the repo root, which documents conventions for working **on this
dotfiles-arch repo** and is never touched by this sync.

Each file is a flat `.mdc` rule (YAML frontmatter + markdown body — see the
[Cursor rules docs](https://cursor.com/docs/context/rules)):

```
rules/
├── some-rule.mdc
└── another-rule.mdc
```

Frontmatter fields: `description`, optional `globs` (comma-separated glob string),
`alwaysApply: true|false`.

`scripts/sync-rules.sh` (run automatically by `dfa-sync-dotfiles`/`bootstrap.sh`, and daily
via `dfa-morning`) symlinks each file here into `~/.cursor/rules/<name>.mdc`, and removes the
symlink again once the file is deleted from its source repo. dotfiles-arch is always
synced first; register extra repos with `dfa-sync-sources add /path/to/repo` (later sources
override on name collision). It never touches anything else already in `~/.cursor/rules/`
— only managed symlinks under `{source}/rules/`. Cursor only; Claude Code has no
equivalent auto-loaded rules directory.

Run it manually with `dfa-sync-rules`.
