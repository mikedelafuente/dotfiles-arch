"""Run python3 tests/test_dark_factory.py. Supplied facts, private /tmp stores only."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "skills/mikedelafuente/dark-factory/scripts/control.py"


def main():
    with tempfile.TemporaryDirectory(prefix="dark-factory-") as temp:
        root = Path(temp)
        artifacts = root / "artifacts"
        artifacts.mkdir()

        def artifact(name, value):
            path = artifacts / name
            path.write_text(json.dumps(value))
            return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

        policy = {
            "actions": ["implement", "evaluate", "commit"],
            "models": {"supplied-sol-6.1": ["medium", "high"], "supplied-opus-5.5": ["standard", "deep"]},
            "families": {"supplied-sol-6.1": "sol-6.1", "supplied-opus-5.5": "opus-5.5"},
            "effort_mapping": [{"max_score": 3, "model": "supplied-sol-6.1", "effort": "medium"},
                               {"max_score": 6, "model": "supplied-sol-6.1", "effort": "high"},
                               {"max_score": 8, "model": "supplied-opus-5.5", "effort": "deep"}],
            "verifier": "fixture-human-verifier-v1", "approval_sources": ["authenticated-human-record"],
            "limits": {"tokens": 100, "seconds": 100, "attempts": 6, "concurrency": 2,
                       "queue": 500, "repairs": 2, "no_progress": 2},
            "deadline": time.time() + 3600, "context": {"entries": 2, "bytes": 3000},
            "artifact_root": str(artifacts)}
        records = {name: artifact(name + ".json", {"fixture": name}) for name in
                   ("charter", "council", "guidance", "proposal", "source", "skills", "decisions")}
        records["criteria"] = artifact("criteria.json", {"checks": ["standards", "spec", "regressions"]})
        records["authority"] = artifact("authority.json", {"policy": policy})

        def receipt(subject, **changes):
            return dict({"actor": "actual-fixture-human", "source": "authenticated-human-record",
                         "timestamp": time.time() - 1, "subject": subject, "status": "accepted",
                         "verifier": "fixture-human-verifier-v1", "verified": True}, **changes)

        bundle = {
            "schema_version": 1, "project": "synthetic-tui", "lineage": "iteration-1", "run": "run-1",
            "policy": policy, "records": records,
            "accepted": {name: receipt(records[name]["sha256"]) for name in
                         ("charter", "guidance", "authority")},
            "selection": {"adapter": artifact("adapter.json", {"kind": "accepted-native-milestone"}),
                          "kind": "github-native-milestone", "target": "repo:milestone:7",
                          "tickets": ["parent", "child"], "descendants": ["child"], "excluded": ["backlog"],
                          "dependencies": {"parent": [], "child": ["parent", "external"]},
                          "satisfied_external": {}, "complete": True, "checkpoint": ["parent"]}}
        source = root / "input.json"

        def run(command, store=None, value=None, success=True, extra=()):
            args = ["python3", str(CONTROL), command]
            if store is not None:
                args.append(str(store))
            if value is not None:
                source.write_text(json.dumps(value))
                args.append(str(source))
            result = subprocess.run(args + list(extra), capture_output=True, text=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return json.loads(result.stdout)

        store = root / "store"
        assert run("init", store, bundle)["phase"] == "awaiting-idea-approval"
        run("init", store, bundle, success=False)  # new wake cannot reset a lineage
        counter = 0

        def event(op, success=True, **fields):
            nonlocal counter
            counter += 1
            value = dict(id=f"event-{counter}", lineage=bundle["lineage"], op=op, **fields)
            return run("apply", store, value, success=success)

        launch = {"ticket": "parent", "owner": "worker-a", "action": "launch-a",
                  "allocation": {"tokens": 40, "seconds": 40},
                  "effort": {"model": "supplied-sol-6.1", "effort": "medium"},
                  "plan": {"scores": {"ambiguity": 0, "integration": 1, "consequence": 1, "validation": 0},
                           "rationale": "Supplied simple fixture", "capability": records["skills"]},
                  "lease_until": time.time() + 60}
        event("reserve", success=False, **launch)  # silence/labels confer no approval
        event("approval", success=False, receipt=receipt(records["proposal"]["sha256"],
                                                        source="assistant-written-label"))
        assert event("approval", receipt=receipt("stale-hash"))["phase"] == "awaiting-idea-approval"
        assert event("approval", receipt=receipt(records["proposal"]["sha256"]))["phase"] == "ready"
        event("reserve", success=False, **dict(launch, ticket="backlog"))
        event("reserve", success=False, **dict(launch, ticket="child"))  # graph gate
        event("reserve", success=False, **dict(launch, effort={"model": "unknown", "effort": "high"}))
        deep = dict(launch["plan"], scores={"ambiguity": 2, "integration": 2, "consequence": 2, "validation": 2})
        assert run("effort-plan", store, deep) == {"model": "supplied-opus-5.5", "effort": "deep"}
        run("effort-plan", store, dict(deep, scores={"ambiguity": 3}), success=False)
        event("reserve", **launch)
        owner = {"ticket": "parent", "owner": "worker-a", "action": "launch-a", "fence": 1, "run": "run-1"}
        event("reserve", success=False, **launch)  # duplicate tick/concurrent scheduler
        terminal = artifact("terminal-a.json", {"runner": "stopped", "task": "worker-a"})
        evidence = artifact("result-a.json", {"diff": "synthetic", "checks": "raw evidence"})
        event("launched", success=False, **owner, evidence=evidence,
              observed={"model": "supplied-sol-6.1", "effort": "high"})
        event("reconcile", success=False, **owner, outcome="failed", terminal={"path": "missing", "sha256": "?"})
        event("launched", **owner, evidence=evidence, observed=launch["effort"])
        event("result", success=False, **dict(owner, fence=0), evidence=evidence, terminal=terminal)
        event("result", **owner, evidence=evidence, terminal=terminal, usage={"tokens": 15, "seconds": 12})
        evaluation = dict(owner, evaluator="reviewer-independent", criteria=records["criteria"]["sha256"],
                          checks=["standards", "spec", "regressions"], evidence=evidence, passed=True)
        event("evaluate", success=False, **dict(evaluation, evaluator="worker-a"))
        event("evaluate", success=False, **dict(evaluation, checks=["spec"]))
        event("evaluate", success=False, **dict(evaluation, criteria="weakened"))
        event("evaluate", **evaluation)
        # A delayed terminal callback cannot undo independently settled acceptance.
        event("reconcile", success=False, **owner, terminal=terminal, outcome="failed")
        event("reconcile", success=False, **owner, terminal=terminal, outcome="cancelled")
        prototype = artifact("prototype.json", {"identity": "commit-fixture", "run": "synthetic command",
                                                "limitations": ["runtime unverified"]})
        assert event("checkpoint", prototype=prototype)["phase"] == "awaiting-user-trial"
        event("reserve", success=False, **dict(launch, ticket="child", action="launch-b"))
        assert run("status", store)["phase"] == "awaiting-user-trial"  # no-op wake
        event("trial", success=False, disposition="accept", receipt=receipt(prototype["sha256"]))
        assert event("trial", disposition="resume", receipt=receipt(prototype["sha256"]))["phase"] == "blocked"
        assert run("packet", store)["used"]["tokens"] == 15  # budget survives fresh process
        event("reserve", success=False, **dict(launch, ticket="child", action="launch-b"))

        # Immutable source/authority/proposal drift blocks affected admission.
        path = Path(records["guidance"]["path"])
        original = path.read_bytes()
        path.write_text("changed guidance")
        event("reserve", success=False, **dict(launch, ticket="child", action="launch-b"))
        path.write_bytes(original)
        event("approval", receipt=receipt(records["proposal"]["sha256"], status="revoked"))
        assert run("status", store)["phase"] == "awaiting-idea-approval"

        # Complete goal acceptance, actual trial disposition, no automatic next target.
        complete = copy.deepcopy(bundle)
        complete["selection"]["satisfied_external"] = {"external": terminal}
        complete["selection"]["checkpoint"] = ["parent", "child"]
        store = root / "complete"
        run("init", store, complete)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        for ticket, action in (("parent", "launch-a"), ("child", "launch-b")):
            current = dict(launch, ticket=ticket, action=action)
            current_owner = dict(owner, ticket=ticket, action=action)
            event("reserve", **current)
            event("launched", **current_owner, evidence=evidence, observed=current["effort"])
            event("result", **current_owner, evidence=evidence, terminal=terminal,
                  usage={"tokens": 10, "seconds": 5})
            event("evaluate", **dict(evaluation, ticket=ticket, action=action))
        event("reconcile", success=False, **dict(owner, ticket="child", action="launch-b"),
              terminal=terminal, outcome="failed")
        event("checkpoint", prototype=prototype)
        assert event("trial", disposition="accept", receipt=receipt(prototype["sha256"]))["phase"] == "completed"
        event("reserve", success=False, **launch)

        # Unknown usage remains conservatively reserved; terminal reconciliation fences late callbacks.
        store = root / "uncertain"
        run("init", store, bundle)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        event("reserve", **launch)
        event("reserve", success=False, **dict(launch, action="replacement"))
        event("reconcile", **owner, terminal=terminal, outcome="cancelled")
        assert run("packet", store)["reserved"]["tokens"] == 40
        event("reserve", success=False, **dict(launch, action="replacement"))
        event("reconcile", **owner, terminal=terminal, outcome="cancelled", usage={"tokens": 5, "seconds": 3})
        event("reserve", **dict(launch, action="replacement"))
        event("launched", success=False, **owner, evidence=evidence, observed=launch["effort"])
        replacement = dict(owner, action="replacement", fence=2)
        event("launched", **replacement, evidence=evidence, observed=launch["effort"])
        event("begin-action", success=False, **replacement, operation="deploy", target="parent", identity="deploy-1")
        event("begin-action", **replacement, operation="commit", target="parent", identity="commit-1")
        event("action-result", **replacement, identity="commit-1", outcome="uncertain", evidence=evidence)
        event("reserve", success=False, **dict(launch, action="another"))
        event("action-result", **replacement, identity="commit-1", outcome="confirmed", evidence=evidence)
        event("begin-action", success=False, **replacement, operation="commit", target="parent", identity="commit-1")

        # Accounting unknown observed usage does not invalidate acceptance.
        store = root / "late-usage"
        run("init", store, bundle)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        event("reserve", **launch)
        event("launched", **owner, evidence=evidence, observed=launch["effort"])
        event("result", **owner, evidence=evidence, terminal=terminal)
        event("evaluate", **evaluation)
        assert run("packet", store)["reserved"]["tokens"] == 40
        event("settle-usage", **owner, evidence=evidence, usage={"tokens": 5, "seconds": 3})
        assert run("packet", store)["reserved"]["tokens"] == 0
        assert event("checkpoint", prototype=prototype)["phase"] == "awaiting-user-trial"

        # Finite repairs, repeated failure signatures and no reset on retries.
        store = root / "repairs"
        run("init", store, bundle)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        for attempt in (1, 2):
            action = f"repair-{attempt}"
            current_owner = dict(owner, action=action, fence=attempt)
            event("reserve", **dict(launch, action=action))
            event("launched", **current_owner, evidence=evidence, observed=launch["effort"])
            event("result", **current_owner, evidence=evidence, terminal=terminal,
                  usage={"tokens": 10, "seconds": 5})
            event("evaluate", **dict(evaluation, action=action, fence=attempt, passed=False, signature="same-failure"))
        event("reserve", success=False, **dict(launch, action="third-repair"))
        assert run("packet", store)["used"]["attempts"] == 2

        # Reservations, observed overruns and deadlines bound resource consumption.
        store = root / "budget"
        run("init", store, bundle)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        event("reserve", success=False, **dict(launch, allocation={"tokens": 101, "seconds": 10}))
        event("reserve", **launch)
        event("launched", **owner, evidence=evidence, observed=launch["effort"])
        assert event("result", **owner, evidence=evidence, terminal=terminal,
                     usage={"tokens": 101, "seconds": 5})["phase"] == "budget-exhausted"
        event("reserve", success=False, **dict(launch, action="after-exhaustion"))
        expired = copy.deepcopy(bundle)
        expired["policy"]["deadline"] = time.time() - 10
        expired["records"]["authority"] = artifact("expired-authority.json", {"policy": expired["policy"]})
        expired["accepted"]["authority"] = receipt(expired["records"]["authority"]["sha256"])
        store = root / "expired"
        run("init", store, expired)
        assert event("approval", receipt=receipt(records["proposal"]["sha256"]))["phase"] == "budget-exhausted"
        event("reserve", success=False, **launch)

        # Observe-only runs retain all attempts, timings and missing telemetry without caps.
        observed = copy.deepcopy(bundle)
        observed["run"] = "observe-run"
        observed["policy"]["budget_mode"] = "observe-only"
        observed["policy"]["deadline"] = None
        for unit in ("tokens", "seconds", "attempts", "repairs"):
            observed["policy"]["limits"][unit] = None
        observed["records"]["authority"] = artifact("observe-authority.json", {"policy": observed["policy"]})
        observed["accepted"]["authority"] = receipt(observed["records"]["authority"]["sha256"])
        aggregate = root / "observations"
        aggregate.mkdir(mode=0o700)
        store = aggregate / "runs" / "first"
        run("init", store, observed)
        uncapped_launch = dict(launch, allocation={"tokens": None, "seconds": None})
        event("reserve", success=False, **uncapped_launch)  # observe-only grants no approval
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        for attempt in (1, 2):
            action = f"observe-{attempt}"
            current = dict(owner, run="observe-run", action=action, fence=attempt)
            event("reserve", **dict(uncapped_launch, action=action))
            event("launched", **current, evidence=evidence, observed=launch["effort"])
            if attempt == 1:
                event("result", **current, evidence=evidence, terminal=terminal,
                      timing={"started_at": 100, "finished_at": 110.5})
                event("evaluate", **dict(evaluation, **current, passed=False, signature="initial-failure"))
            else:
                breakdown = {"tokens": 3000000, "seconds": 45.5, "input_tokens": 2990000,
                             "cached_input_tokens": 2800000, "output_tokens": 10000, "reasoning_tokens": 8000}
                event("result", success=False, **current, evidence=evidence, terminal=terminal,
                      usage=dict(breakdown, tokens=5800000))  # cache/reasoning are subsets
                event("result", success=False, **current, evidence=evidence, terminal=terminal,
                      usage=dict(breakdown, seconds=float("inf")))
                event("result", **current, evidence=evidence, terminal=terminal, usage=breakdown,
                      timing={"started_at": 200, "finished_at": 260})
                event("evaluate", **dict(evaluation, **current))
        # Late usage for the first attempt still settles after a retry replaced its claim.
        first_owner = dict(owner, run="observe-run", action="observe-1", fence=1)
        event("settle-usage", **first_owner, evidence=evidence, usage={"tokens": None, "seconds": 8.5})
        event("settle-usage", **first_owner, evidence=evidence, usage={"tokens": 1000000, "seconds": 8.5})
        event("settle-usage", success=False, **first_owner, evidence=evidence,
              usage={"tokens": 1000001, "seconds": 8.5})
        activity = {"id": "review-metrics", "lineage": observed["lineage"], "run": "observe-run", "op": "activity",
                    "identity": "review-attempt-1", "item": "parent standards/spec review", "ticket": "parent",
                    "phase": "evaluation", "owner": "independent-evaluator", "attempt": 1,
                    "model": "supplied-sol-6.1", "effort": "high", "outcome": "completed",
                    "usage": {"tokens": None, "seconds": 3.25}, "evidence": evidence,
                    "timing": {"started_at": 300, "finished_at": 304.25}}
        run("apply", store, activity)
        run("apply", store, activity)  # replay never double-counts
        run("apply", store, dict(activity, id="duplicate-review"), success=False)
        run("apply", store, dict(activity, id="stale-review", identity="another", run="other"), success=False)
        run("apply", store, dict(activity, id="bad-clock", identity="another",
                                  timing={"started_at": 5, "finished_at": 4}), success=False)
        report = run("report", store)
        assert len(report["items"]) == 3 and report["totals"]["attempts"] == 3
        assert {row["identity"]: row["attempt"] for row in report["items"]} == {"observe-1": 1, "observe-2": 2, "review-attempt-1": 1}
        metrics = report["totals"]["metrics"]
        assert metrics["tokens"]["known_total"] == 4000000 and metrics["tokens"]["missing_items"] == 1
        assert metrics["seconds"]["known_total"] == 57.25
        assert metrics["wall_seconds"]["known_total"] == 74.75
        assert metrics["tokens"]["median"] == 2000000
        parent_item = next(row for row in report["by_item"] if row["item"] == "parent")
        assert parent_item["attempts"] == 2 and parent_item["metrics"]["tokens"]["known_total"] == 4000000
        assert report["timeline"]["observed_span_seconds"] >= 0
        assert {row["effort"] for row in report["by_effort"]} == {"medium", "high"}
        packet = run("packet", store)
        assert packet["used"]["tokens"] == 4000000 and packet["used"]["attempts"] == 3
        assert packet["remaining"]["tokens"] is None and packet["remaining"]["attempts"] is None
        saved = run("report", store, extra=("--write",))
        saved_path = Path(saved["report"]["path"])
        assert saved_path.is_file() and saved_path.stat().st_mode & 0o077 == 0
        assert hashlib.sha256(saved_path.read_bytes()).hexdigest() == saved["report"]["sha256"]
        assert event("checkpoint", prototype=prototype)["phase"] == "awaiting-user-trial"
        event("reserve", success=False, **dict(uncapped_launch, ticket="child", action="trial-bypass"))

        # Project aggregation reads multiple runs, deduplicates identical copies and separates efforts.
        other = copy.deepcopy(observed)
        other["run"] = "another-run"
        second_store = aggregate / "runs" / "second"
        run("init", second_store, other)
        second_activity = dict(activity, id="second-activity", run="another-run", identity="second-activity",
                               phase="research", ticket=None, item="integration research", effort="medium",
                               usage={"tokens": 50, "seconds": 1.5})
        run("apply", second_store, second_activity)
        combined = run("report-project", aggregate)
        assert len(combined["runs"]) == 2 and combined["totals"]["attempts"] == 4
        assert combined["totals"]["metrics"]["tokens"]["known_total"] == 4000050
        assert len(combined["by_effort"]) == 4
        import shutil
        shutil.copytree(second_store, aggregate / "copy")
        assert run("report-project", aggregate)["totals"]["attempts"] == 4
        project_saved = run("report-project", aggregate, extra=("--write",))
        assert Path(project_saved["report"]["path"]).parent == aggregate
        # Changed receipts must fail visibly instead of silently corrupting statistics.
        receipt_file = second_store / "receipts" / (hashlib.sha256(json.dumps("second-activity",
                              separators=(",", ":")).encode()).hexdigest() + ".json")
        original_receipt = receipt_file.read_bytes()
        altered = json.loads(original_receipt); altered["usage"]["tokens"] = 99
        receipt_file.write_text(json.dumps(altered))
        run("report", second_store, success=False)
        receipt_file.write_bytes(original_receipt)
        # Observe-only can retain explicitly chosen caps without losing unknown-use reservations.
        mixed = copy.deepcopy(observed); mixed["run"] = "mixed-run"
        mixed["policy"]["limits"]["tokens"] = 100
        mixed["records"]["authority"] = artifact("mixed-authority.json", {"policy": mixed["policy"]})
        mixed["accepted"]["authority"] = receipt(mixed["records"]["authority"]["sha256"])
        store = root / "mixed-caps"
        run("init", store, mixed)
        event("approval", receipt=receipt(records["proposal"]["sha256"]))
        mixed_launch = dict(launch, allocation={"tokens": 40, "seconds": None})
        mixed_owner = dict(owner, run="mixed-run")
        event("reserve", **mixed_launch)
        event("launched", **mixed_owner, evidence=evidence, observed=launch["effort"])
        event("result", success=False, **mixed_owner, evidence=evidence, terminal=terminal,
              usage={"tokens": None, "seconds": 5})
        event("result", **mixed_owner, evidence=evidence, terminal=terminal)
        event("evaluate", **dict(evaluation, **mixed_owner, passed=False, signature="needs-repair"))
        assert run("packet", store)["reserved"]["tokens"] == 40
        event("reserve", success=False, **dict(mixed_launch, action="mixed-retry"))
        event("settle-usage", **mixed_owner, evidence=evidence, usage={"tokens": 45, "seconds": None})
        event("reserve", success=False, **dict(mixed_launch, action="mixed-retry",
                                                allocation={"tokens": 101, "seconds": None}))
        event("reserve", **dict(mixed_launch, action="mixed-retry"))

        # Null limits remain invalid in legacy bounded policies.
        invalid = copy.deepcopy(observed); invalid["policy"]["budget_mode"] = "bounded"
        run("init", root / "invalid-observe", invalid, success=False)

        # Duplicate receipts are idempotent; altered content under one ID is rejected.
        store = root / "idempotent"
        run("init", store, bundle)
        callback = {"id": "stable-id", "lineage": bundle["lineage"], "op": "approval",
                    "receipt": receipt(records["proposal"]["sha256"])}
        first_receipt = run("apply", store, callback)
        assert run("apply", store, callback)["version"] == first_receipt["version"]
        run("apply", store, dict(callback, receipt=receipt("different")), success=False)

        # Queue/descendant/acceptance/schema gaps fail before initialization.
        for name, changed in (("version", dict(bundle, schema_version=2)),
                              ("incomplete", dict(bundle, selection=dict(bundle["selection"], complete=False))),
                              ("descendant", dict(bundle, selection=dict(bundle["selection"], descendants=["omitted"]))),
                              ("unaccepted", dict(bundle, accepted={})),
                              ("cyclic", dict(bundle, selection=dict(bundle["selection"],
                                dependencies={"parent": ["child"], "child": ["parent"]})))):
            run("init", root / name, changed, success=False)

        # Portable accepted resolver snapshots; no tracker platform selects a convention.
        for kind in ("github-native-milestone", "github-milestone-label-issue", "jira-epic",
                     "jira-labeled-epic", "company-Idea-grouping-epics"):
            changed = copy.deepcopy(bundle)
            changed["selection"]["kind"] = kind
            run("init", root / kind, changed)

        # Growing archived graph/history stays outside the bounded coordinator packet.
        large = copy.deepcopy(bundle)
        tickets = [f"ticket-{index}" for index in range(400)]
        large["selection"].update(tickets=tickets, descendants=tickets, checkpoint=tickets,
                                  dependencies={ticket: [] for ticket in tickets})
        store = root / "large"
        run("init", store, large)
        first = run("packet", store)
        assert len(first["page"]) == 2 and first["next"] == 2
        assert len(json.dumps(first, separators=(",", ":")).encode()) <= policy["context"]["bytes"]
        second = run("packet", store, extra=("--cursor", "2"))
        assert second["page"][0]["ticket"] != first["page"][0]["ticket"]

        # Source-scoped stable retro identity, privacy/destination/authorization and uncertain dedup.
        proposal = {"schema_version": 1, "source": "https://example.org/public/skills",
                    "destination": "https://example.org/public/skills", "skill": "dark-factory",
                    "category": "navigation", "invariant": "missing artifacts park work",
                    "expected": "park", "observed": "continued", "synthetic": True,
                    "evidence": ["private:e1"], "source_verified": True, "lookup_complete": True,
                    "prior_outcome": "absent", "content": "A synthetic worker follows a missing pointer.",
                    "limits": {"count": 2, "tokens": 100, "seconds": 20},
                    "usage": {"count": 0, "tokens": 10, "seconds": 1}}
        content_hash = hashlib.sha256(proposal["content"].encode()).hexdigest()
        proposal["privacy_review"] = {"verified": True, "safe": True, "subject": content_hash, "unresolved": []}
        proposal["approval"] = dict(receipt(content_hash), destination=proposal["destination"])
        identity = run("fingerprint", value=proposal)["fingerprint"]
        assert run("fingerprint", value=dict(proposal, run="later", timestamp=123))["fingerprint"] == identity
        assert run("fingerprint", value=dict(proposal, source="https://example.org/other"))["fingerprint"] != identity
        assert run("publication-check", value=proposal)["fingerprint"] == identity
        for changed in (dict(proposal, source_verified=False), dict(proposal, prior_outcome="uncertain"),
                        dict(proposal, prior_outcome="linked"), dict(proposal, lookup_complete=False),
                        dict(proposal, approval={}), dict(proposal, synthetic=False),
                        dict(proposal, usage={"count": 2, "tokens": 10, "seconds": 1})):
            run("publication-check", value=changed, success=False)
        for private_class in ("private-url", "personal-name", "secret", "proprietary-domain", "raw-transcript"):
            unsafe = dict(proposal, privacy_review={"verified": True, "safe": False,
                          "subject": content_hash, "unresolved": [private_class]})
            run("publication-check", value=unsafe, success=False)

    print("PASS: dark-factory approval, capped/observe-only usage, per-attempt/project reports, trial pauses,")
    print("resume/fencing, drift, portable supplied graphs, bounded packets and retro publication gates")


if __name__ == "__main__":
    main()
