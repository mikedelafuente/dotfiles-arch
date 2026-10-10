# Skills by source

Skills are grouped by provenance; installed names remain flat:

```text
skills/
├── mattpocock/{engineering,productivity,misc}/<skill>/SKILL.md
├── ponytail/<skill>/SKILL.md
├── caveman/<skill>/SKILL.md
├── asd-ste100-skill/SKILL.md
└── mikedelafuente/<skill>/SKILL.md
```

Both `dfa-sync-skills` and the cloud installer recursively discover exact
`SKILL.md` filenames and link their parent folders under the folder basename.
Supporting files stay beside their prompt. Author/category folders and notes are not skills. Matt's category layout is
preserved so reviewed upstream skill files can be copied directly.
Extra skill sources are considered in config order; dotfiles-arch is considered
last and has final priority. A duplicate can replace its current owner only when
that owner's source is marked `overwritable=true`. The default is false: protected
duplicates report a warning/error and stop sync before any target links change.
Mark a company source overwritable to let dotfiles-arch replace its duplicate
`grill-me` while still installing its non-conflicting skills. Replacements from
an overwritable source are silent. Duplicate names within one source always fail.
Rules/extensions retain their existing source-order behavior; this setting applies
to skills only.

```bash
dfa-sync-sources add /path/to/company --overwritable true
# Add --type skills-root if the path is itself a skill tree.
dfa-sync-sources add /path/to/company --overwritable false
```

Re-adding a source updates its setting; omitting the option preserves a saved
setting (new sources default to false). `dfa-sync-sources list` shows it. Existing
config lines remain valid; writable entries add a tab-separated `overwritable=true`
suffix. Remove/reorder operations preserve each source's setting. Existing flat skill sources still work. Internal leaf
symlink aliases are supported; external skill/marker targets are rejected; directory symlinks are not recursively traversed.
Existing unrelated skill entries are preserved. Owned links are updated on moves
and pruned when a skill disappears, including nested sources explicitly removed
through `dfa-sync-sources remove`.

Workstation targets are Claude, Cursor, detected Codex (`$CODEX_HOME/skills`,
default `~/.codex/skills`), and Pi. Run `dfa-sync-skills` after changing the tree.
For cloud use, supply the source checkout explicitly and run
`bash scripts/install-cloud-agent-config.sh --source /path/to/skills --home "$HOME"`; it installs skills
in `.agents/skills` and the shared global rule baseline, without OS setup.
See [cloud setup](../README.md#shared-agent-config-in-cloud-checkouts).

`dfa-sync-sources` manager option **5** toggles skill overwrites for an existing
source. It displays the current setting; changes apply on the next skill sync.

## Pinned imports

| Group | Source | Pinned revision | Contents |
|---|---|---|---|
| `mattpocock` | [mattpocock/skills](https://github.com/mattpocock/skills) | `f3fc5632f401156837ee3872f14fe33ccf1024ea` | 31 selected engineering/productivity/misc skills; experimental skills and repository instructions excluded |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | `552acd5efd0aeae2583a12efe39373d2f076f25e` | Six skill folders; plugin hooks, runtimes, and auto-updaters excluded |

Additional user-supplied imports: `caveman/` contains 22 skills from
[JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman), local source
revision `99aafe151a1be72be783e662858e8a0955add59f`, with its licenses and notice.
`asd-ste100-skill/` contains the self-contained
[danyuchn/asd-ste100-skill](https://github.com/danyuchn/asd-ste100-skill) snapshot
(version 0.4.0 in its metadata; no commit recorded), retaining its MIT license.
These imports bring the installed tree to 71 skill parent folders. Validation
below checks discovery and installation, not a full behavior/security audit of
these additional imported workflows.

Imported prompts and supporting files retain upstream contents, metadata, and
MIT licenses (stored at each source group's root). The copied Matt and Ponytail
snapshots match the upstream revisions recorded above. Personal customizations
live in wrappers rather than edits to those upstream prompts.
`mikedelafuente` contains personal integrations and existing separately maintained
skills, retaining their individual licenses. The shared simplicity rule remains
in `rules/ponytail.mdc`; it adds guidance, not review routing.

## Personal entrypoints

Use [ask-mike](mikedelafuente/ask-mike/SKILL.md) to choose a workflow:

- [advise-me](mikedelafuente/advise-me/SKILL.md) and
  [advise-with-docs](mikedelafuente/advise-with-docs/SKILL.md) load Matt's current
  interview contract and add Council recommendations through `advising`.
  Human answers remain distinct from proposals; the docs variant records accepted
  glossary/ADR decisions through Matt's `domain-modeling`.
- [agent-council](mikedelafuente/agent-council/SKILL.md) supplies relevant product
  and engineering perspectives with bounded debate. See
  [examples and limits](mikedelafuente/agent-council/references/examples.md).
- [council-handoff](mikedelafuente/council-handoff/SKILL.md) prepares accepted
  decisions as input to unchanged `to-spec` or `to-tickets`, preserving checkpoints
  and the user's publication scope. Invoke `/council-handoff spec` or `tickets`.
- [build-with-ponytail](mikedelafuente/build-with-ponytail/SKILL.md) adds Ponytail
  guidance to the selected implementation workflow and owns its combined final review.
- [review-changes](mikedelafuente/review-changes/SKILL.md) delegates once to
  `adversarial-code-review`, which owns independent Standards/Spec reviewers and
  the Ponytail complexity pass. Reviewers return findings without starting another
  coordinator. Reuse this final review and verify only affected findings after fixes.
- [setup-dark-factory](mikedelafuente/setup-dark-factory/SKILL.md) proposes and
  reconciles accepted project council/guidance, tracker conventions and authority.
  [dark-factory-idea](mikedelafuente/dark-factory-idea/SKILL.md) refines new intent
  or a prototype delta and stops for exact versioned human approval.
  [dark-factory](mikedelafuente/dark-factory/SKILL.md) executes only a selected
  authorized finite graph with independent acceptance, then pauses for user trial.
  [dark-factory-supervisor](mikedelafuente/dark-factory-supervisor/SKILL.md)
  reconciles bounded wakes through an accepted runner; it builds nothing and
  creates no schedule. [dark-factory-retro](mikedelafuente/dark-factory-retro/SKILL.md)
  produces private evidence-backed findings; synthetic source-scoped publication
  needs separate content/destination approval. Shared
  [records and control seam](mikedelafuente/dark-factory/references/contracts.md)
  retain approval, optional caps, usage history, claims and trial pauses across resumes.
  Initial observe-only calibration has no user token/time/attempt caps. The
  [usage reports](mikedelafuente/dark-factory/references/metrics.md) preserve each
  item/attempt and aggregate by project, model, effort and phase. Setup accepts
  actual runner/tracker adapters; this package ships no network/runner adapter.

Direct upstream invocations retain upstream behavior: `ask-matt`, `grill-*`,
`code-review`, `to-spec`, `to-tickets`, and Ponytail skills. Personal wrappers resolve
skills by installed name, with relative source links as a fallback. Restoring the
upstream review does not automatically add personal review to every implementation;
use `build-with-ponytail` for that combination. Source grouping changes no harness
invocation syntax: use the syntax supported by your agent.

## Updating an import

Stage downloads outside the active `skills/` tree. Compare the complete staged
snapshot against its recorded pin, including supporting references, executable
scripts, metadata, and licenses. Review for unwanted instructions and side effects;
filename discovery alone establishes no audit or prompt-injection guarantee.
Explicitly accept the reviewed snapshot before replacing the group's selected
skill folders and recording its new commit here. Review deletions too, and preserve
licenses. Then check wrapper compatibility (interview, accepted decisions, docs,
handoffs, and review ownership) and run `dfa-sync-skills`.

Daily sync only installs the committed local snapshot; it does not download or
approve upstream updates. Do not register unaudited upstream checkouts as extra
sync sources. Existing registrations can be removed with
`dfa-sync-sources remove <folder> --type skills-root`.

## Runnable checks

`python3 tests/test_skill_sync.py` and `python3 tests/test_cloud_agent_config.py`
exercise nested discovery, collisions, moves, pruning, and preservation in temporary
homes. `bash scripts/check.sh` checks the shipped shell scripts.
`python3 tests/test_dark_factory.py` checks the local JSON control seam with
supplied approvals/graphs/runner/privacy facts and temporary private stores. It
does not authenticate human evidence, validate a live tracker/runner, certify
semantic privacy or establish real prototype/runtime delivery. Installation and
factory runs remain separate user actions.
