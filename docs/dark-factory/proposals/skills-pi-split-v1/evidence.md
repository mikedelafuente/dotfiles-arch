# Evidence and decisions

User direction: split skills, rules and Pi into the existing skills repository; retain empty primary skills/rules for final overrides. Actual answers: manual source registration; import current files. Latest direction broadens ownership to everything about shared Pi setup. Follow-up explicitly confirms that everything about installing and maintaining Pi belongs to mikedelafuente/skills. This settles ownership; execution/action acceptance remains separate.

Verified bases: dotfiles-arch main 1892b901dc6fb74ac5a5ee49d785315f59d6d277; skills main 4cf0e88b2780ec497af54ab2cb887ec3753eb04b (README and ignore scaffold). Shared edit provenance resolves to the dotfiles checkout. Destination has not been changed.

Two independent read-only discovery agents examined portability and sync/deployment boundaries. Coordinator synthesized product and compatibility requirements; this is not a claim of an independent five-role council or independent acceptance review. No new framework is proposed. The material tradeoff is opt-in standalone Pi ownership versus current automatic workstation Pi installation; the proposal chooses opt-in following the user's ownership direction and awaits approval.

Repository evidence: deployment.py assembles primary then extra sources and currently deploys non-extension Pi files only from primary; skill_discovery.py protects losing sources; sync-rules.sh and sync-extensions.sh currently process primary before extras. Thus today's generic integration does not fully support the requested move, and rule precedence requires an explicit change. Artifact identity remapping must preserve deployment baselines and overrides.

Portability evidence: grouped wrappers rely on relative skill references; Pi merge-pr imports pr-monitor. Preserve complete support trees. Skill-local tests and Pi tests move; workstation integration tests remain. Portable dark-factory references to the former source owner need correction. Upstream pin metadata and licenses travel with their files; unresolved ASD commit provenance remains an explicit gap, not an invented pin.

Primary documentation consulted on 2026-10-09 (America/Phoenix):
- [Pi packages](https://pi.dev/docs/latest/packages): native distribution covers extensions, skills, prompts and themes; package install is explicit.
- [Pi configuration](https://pi.dev/docs/latest/configuration): models/settings/auth and resource locations are separate.
- [Pi settings](https://pi.dev/docs/latest/settings): resource/package path configuration.

These latest docs are evidence, not a tested compatibility promise for the currently configured Pi release. Implementation must verify the installed supported version. Native packaging alone does not cover the complete shared configuration/custom-agent move; retain a small explicit preservation-safe setup seam.

Excluded content: auth.json, models-store.json, credentials, .env files and runtime stores. Shared models.json/settings.json are included without model/default changes.

Readiness: direction is sufficient for a concrete proposal. Full project acceptance, trusted human verifier, cross-repository implementation scope and accepted runner are not yet recorded. No run was initialized and no approval was fabricated. Existing project records remain unchanged.
