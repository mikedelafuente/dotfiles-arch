# Personal skills

Personal Claude Code / Cursor / Codex / Pi skills, tracked here so they follow you across machines.

Each subfolder is one skill and must contain a `SKILL.md` (YAML frontmatter + instructions — see the [Agent Skills spec](https://agentskills.io) / [Claude Code skills docs](https://code.claude.com/docs/en/skills)):

```
skills/
├── some-skill/
│   └── SKILL.md
└── another-skill/
    ├── SKILL.md
    └── references/
```

`scripts/sync-skills.sh` (run automatically by `dfa-sync-dotfiles`/`bootstrap.sh`, and daily via `dfa-daily`) symlinks each folder here into `~/.claude/skills/<name>`, `~/.cursor/skills/<name>`, detected Codex installations under `$CODEX_HOME/skills` (default `~/.codex/skills`), and `~/.pi/agent/skills/<name>`, and removes the symlink again once the folder is deleted from its source repo or the repo is unlisted. dotfiles-arch is always synced first; register extra repos with `dfa-sync-sources add /path/to/repo` (later sources override on name collision). It never touches anything else already in those directories — only managed symlinks under `{source}/skills/`.

Run it manually with `dfa-sync-skills`.

## Vendored Matt Pocock skills

The 31 skills from the configured `engineering`, `productivity`, and `misc` folders
of `mattpocock/skills` are regular files here, copied from commit
`d81f3a183412e71a5b1e84ca21bc1a35eea03a60`. Experimental `in-progress` skills
and upstream repository maintenance instructions are excluded. Each copied skill
includes its supporting files, invocation metadata, and upstream MIT `LICENSE`.
There were no standalone upstream rules to copy into `rules/`.

These copies are maintained here; upstream pulls cannot change them. Review and
copy any desired updates manually. Do not register the upstream skill folders as
extra sync sources: later sources override these local copies. Remove existing
registrations with `dfa-sync-sources remove <folder> --type skills-root`, then run
`dfa-sync-skills` to point installed skills at this repo. The upstream checkout
can then be removed without breaking these skills.
