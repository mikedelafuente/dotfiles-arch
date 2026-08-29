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

`scripts/sync-skills.sh` (run automatically by `dela-sync-dotfiles`/`bootstrap.sh`, and daily via `dela-morning`) symlinks each folder here into `~/.claude/skills/<name>` and `~/.cursor/skills/<name>`, and removes the symlink again once the folder is deleted from its source repo or the repo is unlisted. dotfiles-arch is always synced first; register extra repos with `dela-sync-sources add /path/to/repo` (later sources override on name collision). It never touches anything else already in those directories — only managed symlinks under `{source}/skills/`.

Run it manually with `dela-sync-skills`.
