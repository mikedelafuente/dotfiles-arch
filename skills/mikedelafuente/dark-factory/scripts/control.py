#!/usr/bin/env python3
"""Local supplied-fact control seam. No runner, network or project commands.

The coordinator alone writes the private store after adapter verification.
Run --help; see ../references/contracts.md for the trust and record boundary.
"""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import tempfile
import time


class ContractError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def read(path):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=pairs,
                      parse_constant=lambda value: require(False, f"invalid number: {value}"))


def positive(value):
    return type(value) is int and value > 0


def observed_number(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def observe_only(policy):
    return policy.get("budget_mode", "bounded") == "observe-only"


def within(value, limit):
    return limit is None or value <= limit


def expired(policy):
    return policy["deadline"] is not None and time.time() >= policy["deadline"]


def nullable_units(policy):
    return {unit for unit in ("tokens", "seconds") if observe_only(policy) and policy["limits"][unit] is None}


def usage_valid(usage, partial=()):
    require(isinstance(usage, dict), "invalid observed usage")
    for unit in ("tokens", "seconds"):
        value = usage[unit]
        require((unit in partial and value is None) or
                (type(value) is int and value >= 0 if unit == "tokens" else observed_number(value)),
                f"invalid observed usage: {unit}")
    for unit in ("input_tokens", "cached_input_tokens", "cache_write_tokens", "output_tokens", "reasoning_tokens"):
        value = usage.get(unit)
        require(value is None or type(value) is int and value >= 0, f"invalid token category: {unit}")
    for subset, total in (("cached_input_tokens", "input_tokens"),
                          ("cache_write_tokens", "input_tokens"), ("reasoning_tokens", "output_tokens")):
        if usage.get(subset) is not None and usage.get(total) is not None:
            require(usage[subset] <= usage[total], f"token subset exceeds {total}")
    if all(usage.get(unit) is not None for unit in ("tokens", "input_tokens", "output_tokens")):
        require(usage["tokens"] == usage["input_tokens"] + usage["output_tokens"], "token total double-counted/mismatched")


def timing_valid(timing):
    require(isinstance(timing, dict) and
            all(observed_number(timing.get(unit)) for unit in ("started_at", "finished_at")) and
            timing["finished_at"] >= timing["started_at"], "invalid observed timing")


def text(value):
    return isinstance(value, str) and bool(value.strip())


def reference(ref, root):
    require(isinstance(ref, dict) and text(ref.get("path")), "missing reference path")
    path = Path(ref["path"])
    if not path.is_absolute():
        path = Path(root) / path
    require(not path.is_symlink() and path.is_file(), f"missing/nonregular artifact: {path}")
    require(path.resolve().is_relative_to(Path(root).resolve()), "artifact outside accepted root")
    require(hashlib.sha256(path.read_bytes()).hexdigest() == ref.get("sha256"),
            f"artifact drift: {path}")
    return path


def receipt(item, subject, policy):
    require(isinstance(item, dict), "missing acceptance receipt")
    require(item.get("verified") is True and item.get("verifier") == policy["verifier"],
            "unverified receipt: adapter verification required")
    require(item.get("source") in policy["approval_sources"] and text(item.get("actor")),
            "untrusted approval source/actor")
    require(item.get("subject") == subject and item.get("status") == "accepted",
            "missing, revoked or mismatched approval")
    require(type(item.get("timestamp")) in (int, float) and
            0 < item["timestamp"] <= time.time(), "invalid acceptance timestamp")


def validate(bundle):
    require(bundle["schema_version"] == 1, "incompatible schema version")
    for name in ("project", "lineage", "run"):
        require(text(bundle.get(name)), f"missing {name}")
    policy = bundle["policy"]
    require(policy.get("budget_mode", "bounded") in ("bounded", "observe-only"), "invalid budget mode")
    for name in ("tokens", "seconds", "attempts", "concurrency", "queue", "repairs", "no_progress"):
        require(positive(policy["limits"][name]) or
                (observe_only(policy) and name in ("tokens", "seconds", "attempts", "repairs") and
                 policy["limits"][name] is None), f"invalid limit: {name}")
    require(positive(policy["context"]["entries"]) and positive(policy["context"]["bytes"]),
            "invalid context limits")
    require((observe_only(policy) and policy["deadline"] is None) or
            (type(policy["deadline"]) in (int, float) and math.isfinite(policy["deadline"])),
            "invalid absolute deadline")
    require(text(policy["verifier"]) and policy["approval_sources"], "missing trusted verifier")
    require(isinstance(policy["actions"], list) and policy["actions"], "missing allowed actions")
    require(isinstance(policy["models"], dict) and policy["models"], "missing model capabilities")
    require(all(text(model) and isinstance(efforts, list) and efforts and
                all(text(effort) for effort in efforts)
                for model, efforts in policy["models"].items()), "invalid model/effort capabilities")
    require(set(policy["families"]) == set(policy["models"]) and
            set(policy["families"].values()) <= {"sol-6.1", "opus-5.5"}, "unsupported model family")
    mapping = policy["effort_mapping"]
    require(mapping and mapping[-1]["max_score"] == 8 and
            [row["max_score"] for row in mapping] == sorted(set(row["max_score"] for row in mapping)),
            "invalid accepted effort mapping")
    for row in mapping:
        require(type(row["max_score"]) is int and 0 <= row["max_score"] <= 8 and
                row["model"] in policy["models"] and row["effort"] in policy["models"][row["model"]],
                "effort mapping exceeds capabilities")
    root = policy["artifact_root"]
    records = bundle["records"]
    for name in ("charter", "council", "guidance", "authority", "proposal", "criteria",
                 "source", "skills", "decisions"):
        reference(records[name], root)
    authority = read(reference(records["authority"], root))
    require(authority["policy"] == policy, "policy differs from pinned accepted authority")
    for name in ("charter", "guidance", "authority"):
        receipt(bundle["accepted"][name], records[name]["sha256"], policy)
    criteria = read(reference(records["criteria"], root))
    require(criteria["checks"] and len(criteria["checks"]) == len(set(criteria["checks"])),
            "missing/duplicate mandatory checks")
    selection = bundle["selection"]
    reference(selection["adapter"], root)
    require(text(selection["kind"]) and text(selection["target"]), "missing exact target identity")
    require(selection["complete"] is True, "incomplete hierarchy/membership")
    tickets = selection["tickets"]
    require(tickets and all(text(ticket) for ticket in tickets) and
            len(tickets) == len(set(tickets)), "invalid finite selected ticket set")
    require(len(tickets) <= policy["limits"]["queue"], "selected queue exceeds accepted bound")
    require(set(selection["descendants"]) <= set(tickets), "selected descendant omitted")
    require(not set(selection["excluded"]) & set(tickets), "excluded work selected")
    require(selection["checkpoint"] and set(selection["checkpoint"]) <= set(tickets),
            "invalid checkpoint selection")
    require(set(selection["dependencies"]) == set(tickets), "missing dependency graph nodes")
    visited, active = set(), set()

    def visit(ticket):
        require(ticket not in active, "cyclic selected dependencies")
        if ticket in visited:
            return
        active.add(ticket)
        for dependency in selection["dependencies"][ticket]:
            require(text(dependency), "invalid dependency identity")
            if dependency in tickets:
                visit(dependency)
        active.remove(ticket)
        visited.add(ticket)
    for ticket in tickets:
        visit(ticket)
    for dependency, evidence in selection["satisfied_external"].items():
        require(dependency not in tickets, "external evidence for selected work")
        reference(evidence, root)
    return bundle


def write(path, value):
    data = encoded(value)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".pending-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def totals(state):
    return {unit: sum(claim["allocation"][unit] or 0 for claim in state["claims"].values()
                      if claim["usage"] is None or claim["usage"][unit] is None) for unit in ("tokens", "seconds")}


def eligible(bundle, state):
    selection = bundle["selection"]
    accepted = set(state["accepted_tickets"]) | set(selection["satisfied_external"])
    result = []
    for ticket in selection["tickets"]:
        claim = state["claims"].get(ticket)
        if ticket in accepted or (claim and claim["status"] not in ("failed", "cancelled")):
            continue
        if all(dependency in accepted for dependency in selection["dependencies"][ticket]):
            result.append(ticket)
    return result


def admitted(bundle, state):
    validate(bundle)
    receipt(state["approval"], bundle["records"]["proposal"]["sha256"], bundle["policy"])
    require(state["phase"] not in ("awaiting-user-trial", "completed", "budget-exhausted"),
            "run paused or finished")
    require(not expired(bundle["policy"]), "run deadline exhausted")
    require(not any(item["status"] in ("intended", "uncertain")
                    for item in state["actions"].values()), "uncertain action: reconcile first")


def effort_plan(bundle, plan):
    scores = plan["scores"]
    require(set(scores) == {"ambiguity", "integration", "consequence", "validation"} and
            all(type(score) is int and 0 <= score <= 2 for score in scores.values()),
            "invalid four-score effort plan")
    require(text(plan["rationale"]), "missing effort rationale")
    reference(plan["capability"], bundle["policy"]["artifact_root"])
    tier = next(row for row in bundle["policy"]["effort_mapping"]
                if sum(scores.values()) <= row["max_score"])
    return {"model": tier["model"], "effort": tier["effort"]}


def owned(state, event, historical=False):
    require(event["run"] == state["run"], "stale run callback")
    claim = state["claims"][event["ticket"]]
    if historical and claim["action"] != event["action"]:
        claim = state.get("history", {})[event["action"]]
        require(state["actions"][event["action"]]["target"] == event["ticket"], "wrong historical ticket")
    require(event["owner"] == claim["owner"] and event["fence"] == claim["fence"] and
            event["action"] == claim["action"], "stale owner/fence/action callback")
    return claim


def settle(state, claim, usage, partial=()):
    usage_valid(usage, partial)
    previous = claim["usage"] or {}
    require(all(value is None or usage.get(unit, value) == value for unit, value in previous.items()),
            "settled usage cannot change")
    require(not previous or any(value is not None and previous.get(unit) is None
                               for unit, value in usage.items()), "usage already settled")
    claim["usage"] = dict(previous, **usage)
    usage_valid(claim["usage"], partial)
    for unit in ("tokens", "seconds"):
        state["used"][unit] += (usage[unit] or 0) - (previous.get(unit) or 0)


def refresh(bundle, state):
    if state["phase"] in ("awaiting-idea-approval", "awaiting-user-trial", "completed"):
        return
    limits = bundle["policy"]["limits"]
    if expired(bundle["policy"]) or any(
            not within(state["used"][unit] + totals(state)[unit], limits[unit])
            for unit in ("tokens", "seconds")):
        state["phase"] = "budget-exhausted"
    elif any(action["status"] in ("intended", "uncertain") for action in state["actions"].values()):
        state["phase"] = "blocked"
    elif any(c["status"] in ("reserved", "running") for c in state["claims"].values()):
        state["phase"] = "running"
    elif any(c["status"] == "reported" for c in state["claims"].values()):
        state["phase"] = "evaluating"
    elif eligible(bundle, state):
        state["phase"] = "ready"
    else:
        state["phase"] = "blocked"


def apply_event(bundle, state, event):
    require(event["lineage"] == bundle["lineage"], "wrong lineage")
    operation = event["op"]
    policy = bundle["policy"]
    root = policy["artifact_root"]
    if event.get("timing") is not None:
        timing_valid(event["timing"])
    if event.get("phase") is not None:
        require(text(event["phase"]), "invalid activity phase")
    if operation == "approval":
        item = event["receipt"]
        require(item.get("verified") is True and item.get("verifier") == policy["verifier"] and
                item.get("source") in policy["approval_sources"], "unverified current approval")
        state["approval"] = item
        if item["status"] != "accepted" or item["subject"] != bundle["records"]["proposal"]["sha256"]:
            if state["phase"] not in ("awaiting-user-trial", "completed"):
                state["phase"] = "awaiting-idea-approval"
        elif state["phase"] in ("preparing", "awaiting-idea-approval"):
            receipt(item, bundle["records"]["proposal"]["sha256"], policy)
            state["phase"] = "ready"
    elif operation == "reserve":
        admitted(bundle, state)
        require("implement" in policy["actions"], "implementation action forbidden")
        ticket = event["ticket"]
        require(ticket in eligible(bundle, state), "ticket not eligible/selected or already claimed")
        running = sum(c["status"] in ("reserved", "running") for c in state["claims"].values())
        require(running < policy["limits"]["concurrency"], "concurrency/backpressure limit")
        old = state["claims"].get(ticket)
        if old:
            require(old["terminal"] is not None and all(
                    unit in nullable_units(policy) or old["usage"] is not None and old["usage"][unit] is not None
                    for unit in ("tokens", "seconds")),
                    "prior worker/usage uncertain: reconcile before retry")
            require(within(old["repairs"] + 1, policy["limits"]["repairs"]), "repair limit exhausted")
            require(max(old["failures"].values(), default=0) < policy["limits"]["no_progress"],
                    "repeated failure/no progress")
        require(within(state["used"]["attempts"] + 1, policy["limits"]["attempts"]), "attempt limit exhausted")
        allocation = event["allocation"]
        for unit in ("tokens", "seconds"):
            require(positive(allocation[unit]) or (observe_only(policy) and
                    policy["limits"][unit] is None and allocation[unit] is None), f"invalid reservation: {unit}")
            require(within(state["used"][unit] + totals(state)[unit] + (allocation[unit] or 0),
                           policy["limits"][unit]), f"{unit} budget exhausted")
        effort = event["effort"]
        require(effort["model"] in policy["models"] and
                effort["effort"] in policy["models"][effort["model"]], "unsupported model/effort")
        require(effort == effort_plan(bundle, event["plan"]), "launch differs from accepted effort plan")
        require(text(event["owner"]) and event["lease_until"] > time.time(), "invalid owner/lease")
        action = event["action"]
        require(text(action) and action not in state["actions"] and
                action not in state.get("activities", {}), "duplicate launch action")
        state["used"]["attempts"] += 1
        if old:
            state.setdefault("history", {})[old["action"]] = old
        state["claims"][ticket] = {
            "owner": event["owner"], "fence": old["fence"] + 1 if old else 1,
            "lease_until": event["lease_until"], "action": action,
            "status": "reserved", "allocation": allocation, "usage": None,
            "requested": effort, "observed": None, "terminal": None,
            "repairs": old["repairs"] + 1 if old else 0,
            "failures": old["failures"] if old else {}}
        state["actions"][action] = {"operation": "implement", "target": ticket, "status": "intended"}
        state["phase"] = "running"
    elif operation == "launched":
        claim = owned(state, event)
        require(claim["status"] == "reserved", "launch already observed")
        reference(event["evidence"], root)
        require(event["observed"] == claim["requested"], "launch settings mismatch: reconcile/cancel")
        claim["observed"] = event["observed"]
        claim["status"] = "running"
        state["actions"][claim["action"]]["status"] = "confirmed"
    elif operation == "result":
        claim = owned(state, event)
        require(claim["status"] == "running", "result without verified running launch")
        reference(event["evidence"], root)
        reference(event["terminal"], root)
        claim["terminal"] = event["terminal"]
        claim["evidence"] = event["evidence"]
        if event.get("usage") is not None:
            settle(state, claim, event["usage"], nullable_units(policy))
        claim["status"] = "reported"
        state["phase"] = "evaluating"
    elif operation == "evaluate":
        admitted(bundle, state)
        require("evaluate" in policy["actions"], "evaluation action forbidden")
        claim = owned(state, event)
        require(claim["status"] == "reported", "evaluation before worker report")
        require(text(event["evaluator"]) and event["evaluator"] != claim["owner"],
                "self-approval: independent evaluator required")
        criteria = read(reference(bundle["records"]["criteria"], root))
        require(event["criteria"] == bundle["records"]["criteria"]["sha256"], "weakened/drifting criteria")
        require(set(event["checks"]) == set(criteria["checks"]), "missing required evaluation coverage")
        reference(event["evidence"], root)
        require(type(event["passed"]) is bool, "invalid evaluation result")
        if event["passed"]:
            claim["status"] = "accepted"
            state["accepted_tickets"].append(event["ticket"])
        else:
            require(text(event["signature"]), "missing failure signature")
            signature = event["signature"]
            claim["failures"][signature] = claim["failures"].get(signature, 0) + 1
            claim["status"] = "failed"
            state["phase"] = "repairing"
    elif operation == "reconcile":
        claim = owned(state, event)
        require(claim["status"] in ("reserved", "running", "cancelled", "failed"),
                "terminal reconciliation contradicts reported/accepted work")
        reference(event["terminal"], root)
        require(event["outcome"] in ("cancelled", "failed"), "invalid terminal reconciliation")
        claim["terminal"] = event["terminal"]
        if claim["usage"] is None and event.get("usage") is not None:
            settle(state, claim, event["usage"], nullable_units(policy))
        claim["status"] = event["outcome"]
        state["actions"][claim["action"]]["status"] = "confirmed"
    elif operation == "settle-usage":
        claim = owned(state, event, historical=True)
        require(claim["terminal"] is not None, "usage settlement needs terminal evidence")
        reference(event["evidence"], root)
        settle(state, claim, event["usage"], nullable_units(policy))
    elif operation == "activity":
        require(event["run"] == state["run"], "stale activity run")
        require(text(event["identity"]) and event["identity"] not in state["actions"] and
                event["identity"] not in state.get("activities", {}), "duplicate activity identity")
        require(event.get("ticket") is None or event["ticket"] in bundle["selection"]["tickets"],
                "activity outside selected tickets")
        require(text(event["item"]) and text(event["phase"]) and text(event["owner"]) and
                positive(event["attempt"]), "missing activity identity/phase/attempt")
        require(event["model"] in policy["models"] and event["effort"] in policy["models"][event["model"]],
                "unsupported activity model/effort")
        require(event["outcome"] in ("completed", "failed", "cancelled", "interrupted"), "invalid activity outcome")
        reference(event["evidence"], root)
        usage_valid(event["usage"], nullable_units(policy))
        # Accounting only: this records already authorized work, never admits a launch.
        state.setdefault("activities", {})[event["identity"]] = event["id"]
        for unit in ("tokens", "seconds"):
            state["used"][unit] += event["usage"][unit] or 0
        state["used"]["attempts"] += 1
    elif operation == "checkpoint":
        admitted(bundle, state)
        require(set(bundle["selection"]["checkpoint"]) <= set(state["accepted_tickets"]),
                "checkpoint lacks independent acceptance")
        require(all(c["terminal"] is not None for c in state["claims"].values()),
                "in-flight worker at user-trial checkpoint")
        reference(event["prototype"], root)
        state["prototype"] = event["prototype"]
        state["phase"] = "awaiting-user-trial"
    elif operation == "trial":
        require(state["phase"] == "awaiting-user-trial", "trial disposition outside trial pause")
        receipt(event["receipt"], state["prototype"]["sha256"], policy)
        require(event["disposition"] in ("accept", "resume", "delta"), "invalid trial direction")
        state["trial"] = event
        if event["disposition"] == "accept":
            require(set(bundle["selection"]["tickets"]) == set(state["accepted_tickets"]),
                    "incomplete selected descendants/work")
            state["phase"] = "completed"
        elif event["disposition"] == "resume":
            state["phase"] = "ready"
        # A delta preserves the pause until a separately accepted successor exists.
    elif operation == "begin-action":
        admitted(bundle, state)
        owned(state, event)
        require(event["operation"] in policy["actions"], "external action forbidden")
        require(event["target"] in bundle["selection"]["tickets"], "external action outside selection")
        require(text(event["identity"]) and event["identity"] not in state["actions"] and
                event["identity"] not in state.get("activities", {}),
                "external action already recorded; reconcile outcome")
        state["actions"][event["identity"]] = {
            "operation": event["operation"], "target": event["target"], "status": "intended",
            "claim": {name: event[name] for name in ("run", "ticket", "owner", "fence", "action")}}
    elif operation == "action-result":
        owned(state, event)
        item = state["actions"][event["identity"]]
        require(item.get("claim") == {name: event[name] for name in
                                      ("run", "ticket", "owner", "fence", "action")},
                "action receipt belongs to a different claim/attempt")
        require(item["status"] in ("intended", "uncertain"), "confirmed action cannot replay")
        require(event["outcome"] in ("confirmed", "uncertain"), "invalid action outcome")
        reference(event["evidence"], root)
        item["status"] = event["outcome"]
        item["evidence"] = event["evidence"]
    else:
        raise ContractError(f"unsupported event: {operation}")
    refresh(bundle, state)


def packet(store, bundle, state, cursor):
    limits = bundle["policy"]["context"]
    active = sorted(ticket for ticket, claim in state["claims"].items()
                    if claim["status"] != "accepted")
    frontier = eligible(bundle, state)
    rows = [{"ticket": ticket, "claim": state["claims"].get(ticket)}
            for ticket in dict.fromkeys(active + frontier)]
    require(type(cursor) is int and 0 <= cursor <= len(rows), "invalid packet cursor")
    result = {
        "schema_version": 1, "project": bundle["project"], "lineage": bundle["lineage"],
        "run": bundle["run"], "phase": state["phase"], "version": state["version"],
        "used": state["used"], "reserved": totals(state),
        "remaining": {unit: None if bundle["policy"]["limits"][unit] is None else
                      max(0, bundle["policy"]["limits"][unit] - state["used"][unit] -
                          totals(state).get(unit, 0)) for unit in state["used"]},
        "bundle": {"path": str(store / "bundle.json"), "sha256": digest(bundle)},
        "state": {"path": str(store / "state.json"), "sha256": digest(state)},
        "receipt_index": str(store / "receipts"), "prototype": state.get("prototype"),
        "page": [], "next": cursor if cursor < len(rows) else None}
    require(len(encoded(result)) <= limits["bytes"], "context byte bound too small: checkpoint and pause")
    for row in rows[cursor:cursor + limits["entries"]]:
        candidate = dict(result, page=result["page"] + [row],
                         next=cursor + len(result["page"]) + 1)
        if candidate["next"] == len(rows):
            candidate["next"] = None
        if len(encoded(candidate)) > limits["bytes"]:
            break
        result = candidate
    require(not rows[cursor:] or result["page"], "frontier entry exceeds bound: park; detail is indexed")
    return result


def run_report(store, bundle, state):
    """Rebuild per-attempt observations from committed receipts, including old retries."""
    rows = {}
    events = []
    for key, expected in state["events"].items():
        event = read(store / "receipts" / f"{key}.json")
        if key in state.get("receipt_hashes", {}):
            require(digest(event) == state["receipt_hashes"][key], "usage receipt/timestamp drift")
        received = event.pop("_received_at", None)
        require(digest(event) == expected, "usage receipt drift")
        events.append((event, received))
    order = {op: index for index, op in enumerate(
        ("reserve", "launched", "result", "reconcile", "evaluate", "settle-usage", "activity"))}
    for event, received in sorted(events, key=lambda pair: (pair[1] or 0, order.get(pair[0]["op"], 0))):
        op = event["op"]
        if op not in ("reserve", "launched", "result", "reconcile", "settle-usage", "evaluate", "activity"):
            continue
        identity = event["identity"] if op == "activity" else event["action"]
        row = rows.setdefault(identity, {
            "identity": identity, "ticket": event.get("ticket"), "item": event.get("ticket"),
            "phase": "implementation", "owner": event.get("owner"), "attempt": event.get("fence"),
            "requested": None, "observed": None, "started_at": None, "finished_at": None,
            "timing_source": None, "usage": None, "outcome": "unknown", "evidence": []})
        if "fence" in event:
            row["attempt"] = event["fence"]
        if op == "reserve":
            claim = state["claims"].get(event["ticket"])
            if claim and claim["action"] != identity:
                claim = state.get("history", {}).get(identity)
            row.update(requested=event["effort"], item=event.get("item", event["ticket"]),
                       attempt=claim["fence"] if claim else None,
                       phase=event.get("phase", "repair" if claim and claim["fence"] > 1 else "implementation"),
                       outcome="reserved")
        elif op == "launched":
            row.update(observed=event["observed"], started_at=received, outcome="running")
        elif op in ("result", "reconcile"):
            row.update(finished_at=received, outcome=event.get("outcome", "completed"))
        elif op == "evaluate":
            row["outcome"] = "accepted" if event["passed"] else "failed"
        elif op == "activity":
            row.update(item=event["item"], phase=event["phase"], attempt=event["attempt"],
                       observed={"model": event["model"], "effort": event["effort"]}, outcome=event["outcome"])
        if "usage" in event and event["usage"] is not None:
            row["usage"] = dict(row["usage"] or {}, **event["usage"])
        if event.get("timing") is not None:
            row.update(event["timing"], timing_source="runner-evidence")
        for name in ("evidence", "terminal"):
            if event.get(name) is not None:
                row["evidence"].append(event[name])
    items = []
    for row in rows.values():
        row["wall_seconds"] = (row["finished_at"] - row["started_at"]
                               if row["started_at"] is not None and row["finished_at"] is not None else None)
        if row["wall_seconds"] is not None and row["timing_source"] is None:
            row["timing_source"] = "coordinator-receipt-clock"
        items.append(dict(row, project=bundle["project"], lineage=bundle["lineage"], run=bundle["run"],
                          target=bundle["selection"]["target"], store=str(store.resolve())))
    clocks = [received for _, received in events if received is not None]
    timeline = {"first_receipt_at": min(clocks) if clocks else None,
                "last_receipt_at": max(clocks) if clocks else None,
                "observed_span_seconds": max(clocks) - min(clocks) if clocks else None,
                "source": "coordinator-receipt-clock", "includes_waits": True}
    return {"schema_version": 1, "project": bundle["project"], "lineage": bundle["lineage"],
            "run": bundle["run"], "target": bundle["selection"]["target"], "phase": state["phase"],
            "timeline": timeline, "items": items, **usage_summary(items)}


def usage_summary(items):
    def summarize(rows):
        metrics = {}
        for name in ("tokens", "seconds", "input_tokens", "cached_input_tokens", "cache_write_tokens",
                     "output_tokens", "reasoning_tokens", "wall_seconds"):
            values = [row.get("wall_seconds") if name == "wall_seconds" else
                      (row.get("usage") or {}).get(name) for row in rows]
            known = [value for value in values if value is not None]
            metrics[name] = {"known_total": sum(known), "measured_items": len(known),
                             "missing_items": len(values) - len(known),
                             "mean": statistics.mean(known) if known else None,
                             "median": statistics.median(known) if known else None,
                             "min": min(known) if known else None, "max": max(known) if known else None}
        return {"attempts": len(rows), "metrics": metrics}

    grouped, by_item = {}, {}
    for row in items:
        observed = row["observed"] or {"model": None, "effort": None}
        key = (row["project"], row["phase"], observed["model"], observed["effort"])
        grouped.setdefault(key, []).append(row)
        item_key = (row["project"], row["lineage"], row["run"], row["ticket"], row["item"])
        by_item.setdefault(item_key, []).append(row)
    return {"totals": summarize(items), "by_item": [
        {"project": key[0], "lineage": key[1], "run": key[2], "ticket": key[3], "item": key[4],
         "outcomes": [row["outcome"] for row in rows], **summarize(rows)} for key, rows in by_item.items()],
        "by_effort": [
        {"project": key[0], "phase": key[1], "model": key[2], "effort": key[3], **summarize(rows)}
        for key, rows in grouped.items()]}


def project_report(root):
    reports, identities = [], {}
    # ponytail: scan private run stores on demand; index only if history makes this slow.
    for path in sorted(root.rglob("state.json")):
        store = path.parent
        if not (store / "bundle.json").is_file():
            continue
        require(not path.is_symlink() and not (store / "bundle.json").is_symlink(), "linked report store")
        require(store.stat().st_mode & 0o077 == 0, "report store must be private (0700)")
        with (store / "lock").open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            bundle, state = read(store / "bundle.json"), read(path)
            require(state["bundle_hash"] == digest(bundle), "immutable snapshot changed")
            identity = (bundle["project"], bundle["lineage"], bundle["run"])
            signature = (digest(bundle), digest(state))
            if identity in identities:
                require(identities[identity] == signature, "conflicting copies of one run")
                continue
            identities[identity] = signature
            reports.append(run_report(store, bundle, state))
    items = [item for report in reports for item in report["items"]]
    return {"schema_version": 1, "runs": [{name: report[name] for name in
            ("project", "lineage", "run", "target", "phase", "timeline")} for report in reports],
            "items": items, **usage_summary(items)}


def save_report(root, report):
    path = root / "usage-report.json"
    require(not path.is_symlink(), "report cannot replace symlink")
    write(path, report)
    os.chmod(path, 0o600)
    return {"report": {"path": str(path.resolve()), "sha256": digest(report)}, "totals": report["totals"]}


def fingerprint(proposal):
    return digest({name: proposal[name] for name in
                   ("source", "skill", "category", "invariant", "expected", "observed")})


def publication_check(proposal):
    require(proposal["schema_version"] == 1, "incompatible proposal schema")
    require(proposal["synthetic"] is True and proposal["evidence"], "unsupported/nonsynthetic finding")
    require(proposal["source_verified"] is True and proposal["destination"] == proposal["source"],
            "unknown/mismatched source destination")
    content_hash = hashlib.sha256(proposal["content"].encode()).hexdigest()
    privacy = proposal["privacy_review"]
    require(privacy.get("verified") is True and privacy.get("safe") is True and
            privacy.get("subject") == content_hash and not privacy.get("unresolved", ["missing"]),
            "privacy review missing/unsafe: keep private draft")
    approval = proposal["approval"]
    require(approval.get("verified") is True and approval.get("status") == "accepted" and
            approval.get("subject") == content_hash and
            approval.get("destination") == proposal["destination"] and
            text(approval.get("actor")) and text(approval.get("source")),
            "content/destination approval missing")
    require(proposal["lookup_complete"] is True and proposal["prior_outcome"] == "absent",
            "existing/uncertain publication: reconcile or link")
    for unit in ("count", "tokens", "seconds"):
        limit = proposal["limits"][unit]
        require(positive(limit) or (unit != "count" and observe_only(proposal) and limit is None),
                f"invalid publication limit: {unit}")
        value = proposal["usage"][unit]
        valid = (type(value) is int and value >= 0) if unit != "seconds" else observed_number(value)
        require((limit is None and value is None) or
                (valid and (limit is None or value < limit)), f"publication {unit} exhausted")
    return {"fingerprint": fingerprint(proposal), "content_hash": content_hash,
            "status": "eligible-for-authorized-publication"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("init", "apply", "status", "packet", "effort-plan", "report", "report-project"):
        command = sub.add_parser(name)
        command.add_argument("store", type=Path)
        if name in ("init", "apply", "effort-plan"):
            command.add_argument("input", type=Path)
        if name == "packet":
            command.add_argument("--cursor", type=int, default=0)
        if name in ("report", "report-project"):
            command.add_argument("--write", action="store_true", help="Save private usage-report.json; return its reference")
    for name in ("fingerprint", "publication-check"):
        sub.add_parser(name).add_argument("input", type=Path)
    args = parser.parse_args()
    try:
        if args.command in ("fingerprint", "publication-check"):
            proposal = read(args.input)
            result = ({"fingerprint": fingerprint(proposal)} if args.command == "fingerprint"
                      else publication_check(proposal))
        else:
            store = args.store
            require(not store.is_symlink(), "store cannot be a symlink")
            if args.command == "init":
                store.mkdir(mode=0o700, parents=True, exist_ok=True)
            require(store.is_dir(), "store unavailable")
            require(store.stat().st_mode & 0o077 == 0, "store must be private (0700)")
            if args.command == "report-project":
                result = project_report(store)
                if args.write:
                    result = save_report(store, result)
                print(encoded(result).decode())
                return 0
            with (store / "lock").open("a+") as lock:
                os.chmod(store / "lock", 0o600)
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                if args.command == "init":
                    require(not (store / "bundle.json").exists() and
                            not (store / "state.json").exists(), "lineage already initialized")
                    bundle = validate(read(args.input))
                    write(store / "bundle.json", bundle)
                    state = {"run": bundle["run"], "bundle_hash": digest(bundle), "version": 0,
                             "phase": "awaiting-idea-approval", "approval": None,
                             "used": {"tokens": 0, "seconds": 0, "attempts": 0},
                             "claims": {}, "actions": {}, "accepted_tickets": [], "events": {}}
                    write(store / "state.json", state)
                    (store / "receipts").mkdir(mode=0o700)
                    result = {"phase": state["phase"], "version": 0}
                else:
                    bundle = read(store / "bundle.json")
                    state = read(store / "state.json")
                    require(state["bundle_hash"] == digest(bundle), "immutable snapshot changed")
                    if args.command == "effort-plan":
                        validate(bundle)
                        result = effort_plan(bundle, read(args.input))
                    elif args.command == "apply":
                        event = read(args.input)
                        require("_received_at" not in event, "receipt timestamp is coordinator-owned")
                        require(text(event["id"]), "missing event identity")
                        key = digest(event["id"])
                        previous = state["events"].get(key)
                        if previous:
                            require(previous == digest(event), "event identity reused with different content")
                            result = {"phase": state["phase"], "version": state["version"], "duplicate": True}
                        else:
                            apply_event(bundle, state, event)
                            state["version"] += 1
                            state["events"][key] = digest(event)
                            # Receipt first; interruption before state commit is replayable locally.
                            path = store / "receipts" / f"{key}.json"
                            received = time.time()
                            if path.exists():
                                previous_event = read(path)
                                received = previous_event.pop("_received_at", received)
                                require(previous_event == event, "uncommitted receipt differs: reconcile")
                            recorded = dict(event, _received_at=received)
                            state.setdefault("receipt_hashes", {})[key] = digest(recorded)
                            write(path, recorded)
                            write(store / "state.json", state)
                            result = {"phase": state["phase"], "version": state["version"]}
                    elif args.command == "report":
                        result = run_report(store, bundle, state)
                        if args.write:
                            result = save_report(store, result)
                    else:
                        result = packet(store, bundle, state, args.cursor if args.command == "packet" else 0)
        print(encoded(result).decode())
    except (ContractError, KeyError, TypeError, ValueError, OSError, RecursionError) as error:
        print(encoded({"status": "parked", "reason": str(error)}).decode())
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
