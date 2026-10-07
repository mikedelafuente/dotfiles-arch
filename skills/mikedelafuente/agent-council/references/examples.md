# Invocation and limits

Use `$agent-council` in Codex, `/agent-council` where the harness supports skill
slash commands, `/skill:agent-council` in Pi, or ask “use the agent council.”
These are agent instructions, not shell commands. In an active Pi session, use
`/reload` to refresh skill discovery. `dfa-sync-skills` distributes the folder through the existing
Claude/Cursor/Codex/Pi mechanism; a harness may need a new session to discover it.

- **Neutral idea:** “Use agent-council for a community equipment booking tool.
  We have 30 members, overlapping bookings are a problem, and one maintainer.
  Compare a shared calendar with a custom app.” Works without any project adapter.
- **Simple:** “Use agent-council: should a read-only CSV export of at most 200
  rows run synchronously? Existing endpoint responds in 100 ms, same authorization
  as the page; no scheduling needed.” SE alone checks existing code and standards,
  with one strongest-alternative cross-check. Add SA only if structural concerns emerge.
- **Research:** “Use agent-council to compare maintained booking tools for our
  volunteers and their fit with our three-year plan.” BA checks existing project
  research, fills material gaps about options/workflows, and supplies findings for
  the coordinator to save in `docs/market-research/` unless explicitly told not to;
  PM evaluates strategic fit. Engage technical roles only if a technical constraint
  becomes material.
- **Integration:** “Use agent-council: can our scheduling service synchronize
  with an external calendar?” TPM checks saved integration research for sufficient,
  current evidence before looking up gaps in official integration documentation;
  SE checks existing adapters and standards. Add SA for material design choices,
  BA for unclear synchronization business rules, PM for roadmap tradeoffs.
- **Disputed:** “Use independent agent-council perspectives: shared versus dedicated
  databases for a volunteer scheduling service. A sponsor wants low operating cost;
  one customer asks for isolation; no contractual requirement has been confirmed.”
  Inspect actual evidence, debate isolation/cost, expose contractual choice.
- **Interview:** “/grill-me Sharpen a study-group matching idea; ask me the
  remaining choices.” The coordinator supplies recommendations; fact-finding
  follows grilling's existing delegation.
- **Advising:** “/advise-me Recommend answers for a study-group matching idea;
  ask me the remaining choices.” Council recommendations run for each frontier.
- **With docs:** “/advise-with-docs Advise on docs/brief.md using our
  glossary. Keep my real answers; record accepted terms as they resolve.”
- **Existing Q/A:** “Use agent-council: Q1 Should we offer email reminders?
  Q2 How long should we keep addresses? My answer to Q1 is yes, opt-in only.”
  Preserve Q1's answer; treat retention as a dependent human choice, not consent.
- **Handoff:** “/to-spec Use the accepted council record in
  .scratch/council/booking/agent-output.md; draft locally.” Later: “/to-tickets
  Draft slices from that spec; keep publication local.” Honor each skill's checkpoints.
- **Plain explanation:** `/bro` after an answer re-explains it; it does not rerun
  the council, change decisions, fetch evidence, or write files.

Participation follows the question: use the smallest relevant set, reassess it
for each new advising frontier, and give each research question one owner. Omitted
roles are intentional; a failed selected role is missing coverage.

Limits: role diversity does not prove correctness; source quality and independent
validation matter. Simple mode trades agent independence for cost. Disputed mode
requires delegation or a disclosed fallback. Budget expiry can leave the decision
blocked. The council cannot decide personal values, business commitments, legal
obligations, or grant permissions on behalf of a human. Domain adapters are optional
input, not plugins or required configuration. No external repo, paid service, or
new package is required; no default tracker publishing occurs.
