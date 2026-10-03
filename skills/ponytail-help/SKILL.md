---
name: ponytail-help
description: >
  Quick-reference card for all ponytail modes, skills, and commands.
  One-shot display, not a persistent mode. Trigger: /ponytail-help,
  "ponytail help", "what ponytail commands", "how do I use ponytail".
---

# Ponytail Help

Display this reference card when invoked. One-shot, do NOT change mode,
write flag files, or persist anything.

## Levels

| Level | Trigger | What change |
|-------|---------|-------------|
| **Lite** | `/ponytail lite` | Build what's asked, name the lazier alternative in one line. |
| **Full** | `/ponytail` | The ladder enforced: YAGNI → stdlib → native → one line → minimum. Default. |
| **Ultra** | `/ponytail ultra` | YAGNI extremist. Deletion before addition. Challenges requirements before building. |

Level sticks until changed or session end. These are instruction-based skills,
not the Ponytail plugin. The shared always-apply rule remains active independently
of skill mode switches; disable that rule to turn off its global guidance.

## Skills

| Skill | Trigger | What it does |
|-------|---------|--------------|
| **ponytail** | `/ponytail` | Lazy mode itself. Simplest solution that works. |
| **ponytail-review** | `/ponytail-review` | Over-engineering review: `L42: yagni: factory, one product. Inline.` |
| **ponytail-audit** | `/ponytail-audit` | Whole-repo over-engineering audit: ranked list of what to delete. |
| **ponytail-debt** | `/ponytail-debt` | Harvest `ponytail:` shortcut comments into a tracked ledger. |
| **ponytail-gain** | `/ponytail-gain` | Measured-impact scoreboard: less code, less cost, more speed. |
| **ponytail-help** | `/ponytail-help` | This card. |

In Codex CLI and the IDE extension, invoke skills with `$ponytail`,
`$ponytail-review`, or `$ponytail-help`. Claude Code and OpenCode use the
slash-command forms above (OpenCode ships all six as slash commands).

## Deactivate

Say "stop ponytail" or "normal mode". Resume anytime with `/ponytail`.
`/ponytail off` also works.

## Local installation and updates

These skills and the shared `rules/ponytail.mdc` are vendored in dotfiles-arch.
Run `dfa-sync-skills` and `dfa-sync-rules` to apply local changes. The shared rule
provides always-on simplification guidance to Cursor, Claude, Codex, and Pi through
the existing dotfiles sync. Skill modes apply within the current conversation.

Plugin session hooks, statusline, persistent mode files, environment/config default
levels, and automatic subagent mode injection are not installed by this copy.
Review and copy upstream updates manually into dotfiles-arch; no plugin auto-update.

## More

Full docs + examples: https://github.com/DietrichGebert/ponytail
