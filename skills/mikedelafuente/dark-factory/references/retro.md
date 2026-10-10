# Private retro and publication contract

Analyze only the specified permitted run evidence. Initial observe-only calibration
has no user token/time/attempt cap; explicitly configured caps apply. Keep finite
finding scope and publication-count authorization. Record retro as a distinct
item under [usage reporting](metrics.md) and include it in project effort summaries. Record missing
cost/time telemetry rather than estimating a measured result. Reuse the upstream
`retro` categories and `writing-for-agents`; this wrapper does not build fixes.

Each finding records evidence IDs, affected skill/source revision, classification
(project guidance/ADR, reusable defect or evidence gap), confidence and priority.
Supported reusable proposals include minimal synthetic input, expected versus
observed outcome, acceptance criteria and rationale. Successful patterns are also
evidence; speculation stays a private question. Reproductions are future work,
never executed during retro analysis or publication.

Keep original evidence private under the accepted storage/access/retention policy.
Create the public proposal from synthetic neutral entities and invented sample data,
not by redacting raw evidence. Private URLs, proprietary source/domain/data, personal
names, raw logs/transcripts and secrets are excluded. Meaning surviving redaction
can still disclose the project. A content scan alone cannot certify confidentiality;
require a semantic privacy review against allowed data classes and explicit actual
content/destination approval. Uncertainty means draft/park, not publication.

Resolve source from recorded repository identity/URL, revision and per-skill origin.
Validate current identity/redirects for a moved/renamed repository; do not guess from
basename or edit an installed copy. Missing source, inaccessible revision, denied
permission, offline tracker or missing credentials yields a durable draft with cause.

Generalize a stable finding key before hashing: `source identity + affected skill +
defect category + invariant + synthetic expected/observed behavior`. Exclude run IDs,
timestamps, names and private details so repeated runs deduplicate. Search only that
verified source's tracker and private proposal/action ledger, including uncertain
publication attempts. If found, link it; an update needs separate update authority.
Record a proposed issue's intended source/fingerprint/content hash/action ID before
creation. Persist confirmed issue URL or uncertain outcome before any later attempt.
Reconcile uncertainty against the actual tracker before retry; inability to prove
absence parks the proposal. Never publish the same fingerprint under a new run ID.

`control.py fingerprint PROPOSAL.json` computes the stable generalized identity.
`control.py publication-check PROPOSAL.json` rejects missing synthetic-content
attestation, unresolved source, missing verified content/destination approval,
privacy gaps, configured budget/count exhaustion and duplicate/uncertain publication receipts.
These supplied facts must come from the accepted source/privacy/approval adapters;
the helper cannot authenticate them or guarantee semantic privacy by pattern matching.
Save private proposal and action records before using an authorized tracker tool.

A publication proposal uses schema version 1 and these required fields:
`source`, `skill`, `category`, `invariant`, `expected`, `observed`, `synthetic`,
`evidence`, `privacy_review`, `approval`, `content`, `destination`, `source_verified`,
`lookup_complete`, `prior_outcome`, `limits`, `usage`. `privacy_review` is a verified
reviewer/source receipt covering the exact content hash with `safe: true` and no
unresolved classes; `approval` is a separately verified actual human content/hash/
destination receipt. A supported prior outcome is `absent`, `linked`, `confirmed`
or `uncertain`; only a verified complete `absent` lookup can create a new issue.

Return private evidence plus generalized draft/linked/published/parked outcomes.
No automatic source edits, installation, promotion, recursive retro or executor
dispatch. Accepted authority/criteria/budgets never change to manufacture success.
Active skill versions stay pinned; a future authorized change needs versioned
implementation, replay/regression validation and deliberate later adoption.
