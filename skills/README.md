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

## Vendored Ponytail skills

Six skills from [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail),
version 4.10.3, commit `c982cd411abb53323c4baa1baa3c2f020b8d0b08`, are regular files here with
upstream MIT licenses: `ponytail`, `ponytail-review`, `ponytail-audit`, `ponytail-debt`,
`ponytail-gain`, and `ponytail-help`. The shared rule lives in `rules/ponytail.mdc`.

Only skills and the rule are installed. Help text describes local sync/manual updates
instead of plugin hooks or auto-updates; gain identifies its historical benchmark.
The always-apply rule is independent of skill mode switches. Review desired upstream
updates manually; no upstream checkout or plugin runtime is required.

## Combined review workflow

`ponytail → code-review → adversarial-code-review → ponytail-review`

Ponytail calls the standard review path after implementation and required checks.
If a Matt Pocock workflow already schedules final review, it owns that call.
`code-review` only delegates. `adversarial-code-review` owns Matt's fixed-point
validation, originating-spec discovery, full Fowler smell baseline, independent
Standards/Spec review, separate reports, and per-axis summary. The council integration below also extends `grilling`, `to-spec`, and
`to-tickets`; other Matt Pocock skills retain their pinned upstream contents.

[adversarial-code-review](adversarial-code-review/SKILL.md) owns the single pair of
independent reviewers. Standards adds the Ponytail complexity pass (or
`ponytail-audit` for an explicit codebase audit); Spec independently checks behavior
and requirements. The complexity passes are leaves and return findings without
calling another coordinator. Reviewers execute their assigned role without
starting another pair. This keeps review calls one-way.

The adversarial skill generalizes the Trellis review by discovering the target
repository's language, API, testing, architecture, and compatibility policies.
Committed and working changes share one baseline and coverage inventory. Missing
comparison points prompt for a fixed point. Confirmed absence of a spec skips
specification conformance; added adversarial correctness checks continue separately.
Whole-repository audits require an explicit request. Ponytail can be turned off for the review;
repository rules and required tests still apply.

## Product council

[agent-council](agent-council/SKILL.md) adds five product and engineering
perspectives for any project. Simple questions use five compact lenses; disputed
questions use independent agents with bounded challenge and convergence.
`/grill-me` and `/grill-with-docs` can request council-backed recommendations
while retaining real human answers. Accepted records carry into `/to-spec` and
`/to-tickets`; unresolved material choices remain explicit. `/bro` re-explains
the human summary. See [invocations and limits](agent-council/references/examples.md).
No new shell command, package, or upstream checkout is required.
