# Skills and standalone Pi ownership — revision 2

Status: awaiting-idea-approval. This is a planning draft, not an execution receipt.

## Problem
Personal skills, shared agent rules, and Pi setup currently belong to the workstation repository. Sharing these resources should not require adopting the workstation. The user also wants the workstation's empty skills and rules directories to remain available for final local overrides.

## Solution
Import current shared contents into the existing mikedelafuente/skills repository, preserving its initial scaffolding, grouped layout, licenses, upstream pins, relative references and portable tests. Make that repository the owner of the entire shared Pi setup: installation, update instructions/tooling, settings, models, extensions, prompts, custom agents, documentation and Pi-specific tests. Pi becomes an explicitly opted-in setup. All Pi-specific installation and maintenance belongs to mikedelafuente/skills: CLI acquisition, prerequisite checks, version/owner checks, refresh/update, health checks, repair, removal instructions and Pi-specific configuration maintenance. Dotfiles retains no Pi-specific installer, updater or maintenance wrapper. Generic source syncing and harness launching remain in dotfiles.

The workstation retains generic source registration, resource discovery, stable deployment generations, harness launching and integration tests. It consumes registered data without executing source-provided setup scripts. The user registers the new source manually; neither fresh bootstrap nor daily sync acquires or registers it automatically.

## User stories
- A user shares an individual skill without requiring workstation setup.
- A Pi user installs and updates Pi through the skills repository with documented prerequisites.
- A workstation user manually registers the skills repository and receives shared resources through existing generation deployment.
- A workstation user adds a personal primary-source rule or skill override with documented collision protection.
- An existing user retains local edits, explicit overrides, credentials and runtime state across the source move.

## Implementation decisions
1. Snapshot import only; do not rewrite history. Preserve existing destination README and ignore rules by integrating documentation.
2. Keep grouped skills together. Move personal shared rules; retain project-only agent guidance and conventions in the workstation repository. Empty primary skills/rules directories use inert placeholders because Git cannot track empty directories.
3. Pi's native package mechanism handles extensions, skills and prompts for standalone consumers. Models, shared settings and custom agent resources require explicit, preservation-safe setup. Native packages do not automatically install those additional configuration files. Use one resource-loading route per consumer; a workstation deployment must not also load duplicate native package resources.
4. Retain the existing Node 22+ user-owned installation contract and Pi's npm lifecycle-script restriction. The standalone owner supplies explicit installation/update tooling without copying the workstation helper framework. Remove Pi acquisition from the workstation default setup list and Pi-specific npm update ownership after the replacement is available. Keep generic Pi harness detection/launch support.
5. Extend the generic standard-source data integration to consume shared Pi configuration and custom agents/prompts, in addition to extensions. Preserve generation-based deployment; do not replace it with raw checkout links.
6. Make primary workstation rules final in all consumers, including concatenated global instructions. Preserve skill collision protection: a primary replacement is allowed only when the losing extra source is explicitly overwritable. Registration remains a user action.
7. A source relocation is an identity migration, not a delete/add. Preserve three-way baselines, persistent overrides and local changes when primary artifact identities become extra-source identities. Conflicts block the whole generation. Test legacy models-store links before removing source files; never import credential or runtime stores.
8. Separate source ownership from project factory configuration. Project records and historical evidence remain in the workstation repo. Correct portable skill references that hardcode their former owner; create successor project pins rather than rewriting historical approvals.
9. Publish/commit the replacement snapshot before contracting the original source. Cross-repository changes must be reviewable together. Publication, deployment and live workstation trials require their own action authority.

## Testing decisions
Prove byte-identical import inventory with explicit exclusions, working relative references, retained license/pin provenance, and portable test execution. In temporary homes, test source ordering, protected collisions, full Pi data delivery, duplicate-load avoidance, clean and locally edited identity migrations, explicit overrides, conflicts, legacy links, source disappearance, rerun idempotence and rollback. Test cloud installation with an explicitly supplied source; no automatic registration or acquisition. Run existing workstation gates after ownership moves.

## Scope and non-goals
No model/default changes, Pi fork, new orchestration framework, upstream skill upgrades, history import, automatic cloning/registration, credential migration, live deployment or automatic tracker publication. Move shared Pi setup only; preserve machine-local state. The previously mentioned pi-dev workspace is absent and is not fabricated.

## Checkpoints and recovery
First produce a usable standalone snapshot while retaining the original source. Next prove the generic consumer in fixtures. Finally prove the source handoff and prepare a reproducible trial. Pause for the human before live cutover. Roll back through retained deployment generations and the previous source mapping; keep both repositories available until the handoff is verified. A removed or unregistered source must produce an explicit actionable result and must not silently destroy user files.

## Further notes
GitHub milestones group approved changes. This draft has no milestone or issue yet. Initial token/time/attempt policy stays observe-only; platform limits and approval/trial gates still apply. Cross-repository scope and trusted approval/runner adapters remain unaccepted.
