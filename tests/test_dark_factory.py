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

    print("PASS: dark-factory approval, claims, finite budgets, independent acceptance, trial pauses,")
    print("resume/fencing, drift, portable supplied graphs, bounded packets and retro publication gates")


if __name__ == "__main__":
    main()
