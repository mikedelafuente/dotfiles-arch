# T3 — Preserve state during the source handoff and contract the old owner

Dependencies: T1, T2. Repositories: dotfiles-arch and skills.

Map old/new artifact identities with baseline and override preservation; prove local-edit/conflict/legacy-link/rollback cases. Replacement snapshot must be committed and available before old content removal. Remove the original portable payload, keep inert empty skills/rules directories, retain project conventions, and remove every Pi-specific installer/updater/maintenance implementation or wrapper from dotfiles while retaining generic harness launching and data-source syncing. Update source-owner docs and project successor references without rewriting historical records.

Acceptance: C5, C6, full C7, C8. Selected checkpoint: reproducible fixture handoff. Pause for human trial; do not deploy the live workstation as part of the fixture work.

Proposed four scores: ambiguity 1, integration 2, consequence 2, validation 2; total 7; gpt-6.1-sol/xhigh.
