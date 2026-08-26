# Personal skills

Personal Claude Code / Cursor skills, tracked here so they follow you across machines.

Each subfolder is one skill and must contain a `SKILL.md` (YAML frontmatter + instructions — see the [Agent Skills spec](https://agentskills.io) / [Claude Code skills docs](https://code.claude.com/docs/en/skills)):

```
skills/
├── some-skill/
│   └── SKILL.md
└── another-skill/
    ├── SKILL.md
    └── references/
```

`scripts/sync-skills.sh` (run automatically by `sync-dotfiles`/`bootstrap.sh`, and daily via `morning`) symlinks each folder here into `~/.claude/skills/<name>` and `~/.cursor/skills/<name>`, and removes the symlink again once the folder is deleted from this repo. It never touches anything else already in those directories (e.g. company-provided skills copied in separately on a work machine) — only symlinks it created that point back into this repo.

Run it manually with `sync-skills`.
