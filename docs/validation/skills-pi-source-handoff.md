# Skills/Pi source handoff prototype

Selected target: [Skills repository split and standalone Pi ownership](https://github.com/mikedelafuente/dotfiles-arch/milestone/1).
Frozen proposal revision 2:
`e5c654c83bf860528a8f1e7cbf4377a11509ef7553cd110fec24fa2d1ddc9d34`.

The human authorized the interactive fallback across both repositories and merges
as needed. This delivery uses that route; it does not claim admitted factory
authority, certified runner isolation, or an accepted unattended schedule. The
historical setup/proposal records remain unchanged. Machine checks and the human
trial disposition are separate.

## Reproduce the fixture checkpoint

Keep both repository checkouts available. Prerequisites: Git, Bash, Python 3.11+
and shellcheck for workstation checks; use the skills repository's documented
prerequisites for its portable Pi checks. These commands write only temporary
fixtures and do not deploy, install packages, change services or contact a network:

```bash
# In dotfiles-arch:
python3 tests/test_source_handoff.py
python3 tests/test_deployment.py
python3 tests/test_skill_sync.py
python3 tests/test_cloud_agent_config.py
bash scripts/check.sh

# In skills:
# Run the portable gate documented in that repository's README.
```

The handoff check covers clean and locally edited moves, persistent overrides and
their new-key edits/removal, source pre-registration, competing edits, independently
edited replacement copies, missing registration/source, rerun idempotence,
resolving legacy models-store detachment, credentials and rollback. The generic
consumer and cloud checks verify complete registered data, final primary rules,
protected skill collisions and explicit cloud source selection.

## Human trial

Run the fixture checkpoint and inspect the preservation/conflict results. Confirm
that standalone Pi ownership, manual registration and the preserved generic
workstation commands match the intended workflow. Return an explicit accept or
describe the change you want before a live cutover. This delivery stops awaiting
that feedback. The milestone remains open until actual trial disposition.

Live deployment is a separate workstation action. Before any future live cutover,
retain both repositories, inspect `dfa-deploy status` and existing source settings,
verify any legacy models-store link resolves and has been detached safely, then
follow the standalone owner's mutually exclusive resource-loading routes. The
workstation route manually registers the new standard source and uses installed
generations; it does not also install the native Pi resource package.

Rollback uses the retained generation and prior source mapping. Keep source
checkouts available for legacy-link rollback. A broken legacy state link requires
restoring its original source before retrying; credentials/runtime state are not
imported into the replacement snapshot.

## Limits and observations

Fixture checks prove supplied filesystem and ownership behavior. Real npm
acquisition, a running Pi extension session, desktop/hardware behavior and live
workstation cutover remain runtime-unverified. No upstream versions or model
defaults change. Per-agent token/cache/reasoning counters, observed model/effort
and exclusive active time are unavailable in this runner and are recorded as
unknown, not estimated. Private run observations and evaluator evidence remain
outside worker worktrees; publication of these detailed records is not implied.
