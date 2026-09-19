import assert from "node:assert/strict";
import test from "node:test";
import type { AgentSession } from "./coordinator.ts";
import { renderSessions } from "./messages.ts";
import { CONTROL_TOPIC, FakePiSession, GROUP, harness, OWNER, startWith, tick, until, type Harness } from "./test-support.ts";

/** Sends an owner message in the control topic and waits for the bridge's reply there. */
async function control(h: Harness, text: string): Promise<string> {
	const before = h.telegram.inTopic(CONTROL_TOPIC).length;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text });
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).length > before, 2000);
	return h.telegram.inTopic(CONTROL_TOPIC).at(-1)!.text;
}

/** Has an agent run and answer once, which writes its Pi history, and waits until its session is no longer unprompted. */
async function prompted(h: Harness, session: AgentSession): Promise<void> {
	const agent = h.pi.processes.findLast((process) => process.id === session.piSessionId)!;
	agent.report({ type: "run-start", prompt: "hi" });
	agent.report({ type: "response", text: "hello" });
	agent.report({ type: "settled" });
	await until(() => h.stores.sessions.items.find((item) => item.id === session.id)?.unprompted === undefined);
}

test("new sessions are rejected until remote control is running", async () => {
	const h = await harness();
	await assert.rejects(h.coordinator.newSession({ name: "fix-ci", current: new FakePiSession() }), { code: "not-running" });
	assert.deepEqual(h.workspaces.created, []);
});

test("/rc new from the main line creates an isolated workspace, branch, Pi session, and session topic together", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);

	const { session, adopted } = await h.coordinator.newSession({ name: "Fix CI", current });
	assert.equal(adopted, false);
	assert.deepEqual(h.workspaces.created, [{ path: "/work/demo.worktrees/rc-fix-ci", branch: "rc/fix-ci", created: true }]);
	assert.equal(session.workspace, "/work/demo.worktrees/rc-fix-ci");
	assert.equal(session.branch, "rc/fix-ci");
	assert.equal(session.repositoryPath, "/work/demo");
	assert.equal(session.piSessionId, h.pi.last.id);
	assert.equal(session.piSessionFile, h.pi.last.sessionFile);
	assert.equal(session.topicName, "demo / Fix CI / rc/fix-ci");
	assert.equal(h.telegram.topics.at(-1), "demo / Fix CI / rc/fix-ci");
	assert.deepEqual(h.stores.sessions.items.map((item) => item.name), ["fix-flake", "Fix CI"]);
	assert.equal(h.pi.last.name, "Fix CI");

	const topic = Number(session.topicId);
	assert.ok(h.telegram.inTopic(topic).some((message) => /connected/i.test(message.text)));
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "make the build green" });
	await until(() => h.pi.last.delivered.length === 1);
	assert.deepEqual(h.pi.last.delivered, [["prompt", "make the build green"]]);
	assert.deepEqual(current.delivered, [], "the current conversation keeps its own topic");

	h.pi.last.report({ type: "run-start", prompt: "make the build green" });
	h.pi.last.report({ type: "response", text: "Green." });
	h.pi.last.report({ type: "settled" });
	await until(() => h.telegram.inTopic(topic).some((message) => message.text === "Green."));
});

test("a failed creation rolls back the topic, Pi session, and workspace it already made", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const send = h.telegram.sendMessage.bind(h.telegram);
	h.telegram.sendMessage = async (input) => {
		if (input.threadId !== undefined && input.threadId > 502) throw new Error("fetch failed");
		return send(input);
	};

	await assert.rejects(h.coordinator.newSession({ name: "fix-ci", current }), /fetch failed/);
	assert.equal(h.pi.last.closed, true);
	assert.deepEqual(h.telegram.deleted, [503]);
	assert.deepEqual(h.workspaces.removed, ["/work/demo.worktrees/rc-fix-ci"]);
	assert.equal(h.stores.sessions.items.length, 1, "only the current conversation");
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);

	h.pi.failNext = new Error("pi failed to start");
	await assert.rejects(h.coordinator.newSession({ name: "other", current }), /pi failed to start/);
	assert.deepEqual(h.workspaces.removed, ["/work/demo.worktrees/rc-fix-ci", "/work/demo.worktrees/rc-other"]);
});

test("/rc new on a feature branch adopts the current workspace and conversation instead of duplicating them", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const current = new FakePiSession();
	current.branch = "feat/login";
	h.workspaces.branches.set("/work/demo", "feat/login");
	const { topic } = await startWith(h, current);

	const { session, adopted } = await h.coordinator.newSession({ name: "login", current });
	assert.equal(adopted, true);
	assert.deepEqual(h.workspaces.created, []);
	assert.deepEqual(h.pi.processes, []);
	assert.deepEqual(current.renamedTo, ["login"]);
	assert.equal(session.workspace, "/work/demo");
	assert.equal(session.branch, "feat/login");
	assert.equal(Number(session.topicId), topic, "the conversation keeps its topic");
	assert.deepEqual(h.telegram.renamed, [{ threadId: topic, name: "demo / login / feat/login" }]);
	assert.equal(h.stores.sessions.items.length, 1);
	assert.deepEqual(h.coordinator.status().topics, ["demo / login / feat/login"]);

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "continue" });
	await until(() => current.delivered.length === 1);
});

test("/rc new in a linked worktree adopts that worktree, even on a main-line branch name", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const current = new FakePiSession();
	current.workspace = "/work/demo.worktrees/hotfix";
	current.branch = "master";
	h.workspaces.branches.set(current.workspace, "master");
	await startWith(h, current);

	const { session, adopted } = await h.coordinator.newSession({ name: "hotfix", current });
	assert.equal(adopted, true);
	assert.equal(session.workspace, "/work/demo.worktrees/hotfix");
	assert.equal(session.repositoryPath, "/work/demo");
	assert.deepEqual(h.workspaces.created, []);
});

test("remote /rc new only reaches approved repositories and always creates an isolated workspace", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	await startWith(h);

	assert.match(await control(h, "/rc new /etc pwn"), /not approved.*demo/is);
	assert.match(await control(h, "/rc new demo"), /usage: \/rc new <repository> <name>/i);
	const reply = await control(h, "/rc new demo fix ci");
	assert.match(reply, /demo \/ fix ci \/ rc\/fix-ci/);
	assert.deepEqual(h.workspaces.created.map((workspace) => workspace.branch), ["rc/fix-ci"]);
	assert.equal(h.pi.last.name, "fix ci");
});

test("a second session with the same name, or one claiming an assigned workspace, is rejected", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const first = await h.coordinator.newSession({ name: "fix-ci", current });

	await assert.rejects(h.coordinator.newSession({ name: "FIX-CI", current }), { code: "duplicate-session" });

	// A stored session already owns the workspace the next creation would get.
	h.stores.sessions.items.push({ ...first.session, id: "session-old", name: "old", workspace: "/work/demo.worktrees/rc-taken" });
	await assert.rejects(h.coordinator.newSession({ name: "taken", current }), { code: "duplicate-workspace" });
	assert.ok(h.workspaces.removed.includes("/work/demo.worktrees/rc-taken"), "the workspace just created is removed again");

	// The current conversation moved into the worktree a running agent owns.
	const intruder = new FakePiSession();
	Object.assign(intruder, { id: "pi-intruder", workspace: first.session.workspace, branch: "rc/fix-ci" });
	await assert.rejects(h.coordinator.newSession({ name: "mine", current: intruder }), { code: "duplicate-workspace" });
	assert.equal(h.pi.processes.filter((process) => !process.closed).length, 1);
});

test("/rc sessions groups agent sessions by repository with their health", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const running = await h.coordinator.newSession({ name: "running", current });
	const exited = await h.coordinator.newSession({ name: "exited", current });
	const gone = await h.coordinator.newSession({ name: "gone", current });
	const forgotten = await h.coordinator.newSession({ name: "forgotten", current });
	await prompted(h, forgotten.session);
	await h.coordinator.registerRepository("/work/other");
	h.stores.sessions.items.push({ ...exited.session, id: "session-elsewhere", name: "elsewhere", repositoryPath: "/work/other", workspace: "/work/other" });
	h.workspaces.branches.set("/work/other", "main");
	h.pi.histories.add(exited.session.piSessionFile!);

	for (const { session } of [exited, gone, forgotten]) h.pi.processes.find((process) => process.id === session.piSessionId)!.events.exited("killed");
	h.workspaces.branches.delete(gone.session.workspace);
	h.pi.histories.delete(forgotten.session.piSessionFile!);

	const groups = await h.coordinator.sessions();
	assert.deepEqual(groups.map((group) => [group.repository.name, group.sessions.map((session) => [session.name, session.status])]), [
		["demo", [["fix-flake", "active"], ["running", "active"], ["exited", "disconnected"], ["gone", "missing-workspace"], ["forgotten", "stale"]]],
		["other", [["elsewhere", "disconnected"]]],
	]);
	assert.equal(groups[0].sessions[1].id, running.session.id);

	const reply = await control(h, "/rc sessions");
	assert.match(reply, /demo[\s\S]*running[\s\S]*rc\/running[\s\S]*other[\s\S]*elsewhere/);
	assert.match(reply, /gone.*missing workspace/i);
	assert.match(reply, /forgotten.*stale/i);
});

test("an agent whose Pi process exits is disconnected from its topic until attached again", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	const topic = Number(session.topicId);
	const first = h.pi.last;

	first.events.exited("exit code 1");
	await until(() => h.telegram.inTopic(topic).some((message) => /disconnected.*exit code 1/i.test(message.text)));
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "hello?" });
	await until(() => h.telegram.inTopic(topic).some((message) => /not connected/i.test(message.text)));

	h.workspaces.branches.set(session.workspace, "rc/fix-ci-2");
	assert.match(await control(h, "/rc attach fix-ci"), /reconnected/i);
	const resumed = h.pi.last;
	assert.notEqual(resumed, first);
	assert.equal(resumed.id, session.piSessionId, "the persisted Pi session is resumed, not replaced");
	assert.deepEqual(h.telegram.renamed, [{ threadId: topic, name: "demo / fix-ci / rc/fix-ci-2" }]);
	assert.equal(h.stores.sessions.items.find((item) => item.id === session.id)?.branch, "rc/fix-ci-2");

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "carry on" });
	await until(() => resumed.delivered.length === 1);
});

test("attach replaces a session topic deleted in Telegram", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	h.pi.last.events.exited("killed");
	h.telegram.deletedTopics.add(Number(session.topicId));

	const { session: attached } = await h.coordinator.attach(session.id);
	assert.notEqual(attached.topicId, session.topicId);
	assert.equal(h.stores.sessions.items.find((item) => item.id === session.id)?.topicId, attached.topicId);
});

test("attach refuses missing workspaces, stale sessions, and unknown or ambiguous sessions without starting Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const gone = await h.coordinator.newSession({ name: "gone", current });
	const stale = await h.coordinator.newSession({ name: "stale", current });
	await prompted(h, stale.session);
	await h.coordinator.newSession({ name: "twin", current });
	await h.coordinator.registerRepository("/work/other");
	h.stores.sessions.items.push({ ...stale.session, id: "session-twin-2", name: "twin", repositoryPath: "/work/other", workspace: "/work/other" });
	for (const process of h.pi.processes) process.events.exited("killed");
	h.workspaces.branches.delete(gone.session.workspace);
	h.pi.histories.delete(stale.session.piSessionFile!);
	const started = h.pi.processes.length;

	await assert.rejects(h.coordinator.attach("gone"), { code: "missing-workspace" });
	await assert.rejects(h.coordinator.attach(stale.session.id), { code: "stale-session" });
	await assert.rejects(h.coordinator.attach("nobody"), { code: "session-not-found" });
	await assert.rejects(h.coordinator.attach("twin"), { code: "ambiguous-session" });
	assert.equal(h.pi.processes.length, started);
	assert.match(await control(h, "/rc attach gone"), /workspace.*no longer exists/i);
});

test("attaching a connected session reports it instead of starting a second Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current, session: exposed } = await startWith(h);
	const created = await h.coordinator.newSession({ name: "fix-ci", current });
	const started = h.pi.processes.length;

	assert.equal((await h.coordinator.attach("fix-ci")).alreadyConnected, true);
	assert.equal((await h.coordinator.attach(exposed.id)).alreadyConnected, true);
	assert.equal(h.pi.processes.length, started);
	assert.equal(created.session.id, (await h.coordinator.attach(created.session.id)).session.id);
});

test("stopping remote control leaves agents running; restarting routes them again; shutdown closes them", async () => {
	const h = await harness();
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	const agent = h.pi.last;
	const topic = Number(session.topicId);

	await h.coordinator.stop();
	assert.equal(agent.closed, false);
	await startWith(h, current);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main", "demo / fix-ci / rc/fix-ci"]);
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "still there?" });
	await until(() => agent.delivered.length === 1);

	await h.coordinator.shutdown();
	assert.equal(agent.closed, true);
	assert.equal(h.coordinator.status().running, false);
	await tick();
});

test("control-topic text that is not a /rc command still reaches the local notification handler", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const seen: string[] = [];
	await startWith(h, new FakePiSession(), async (message) => { seen.push(message.text); });
	assert.match(await control(h, "/rc help"), /\/rc new <repository> <name>/);
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "just saying hi" });
	await until(() => seen.length === 1);
	assert.deepEqual(seen, ["just saying hi"]);
});

test("the repository's default branch counts as the main line, whatever it is called", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	h.workspaces.mainLineBranch = "develop";
	const current = new FakePiSession();
	current.branch = "develop";
	await startWith(h, current);

	const { adopted, session } = await h.coordinator.newSession({ name: "fix-ci", current });
	assert.equal(adopted, false);
	assert.equal(session.branch, "rc/fix-ci");
});

test("names that would share a branch are duplicates", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	await h.coordinator.newSession({ name: "Fix bug", current });
	await assert.rejects(h.coordinator.newSession({ name: "fix-bug", current }), { code: "duplicate-session" });
	assert.equal(h.workspaces.created.length, 1);
});

test("attach refuses sessions whose repository is no longer approved", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	h.pi.last.events.exited("killed");
	await h.stores.repositories.remove("/work/demo");
	const started = h.pi.processes.length;

	await assert.rejects(h.coordinator.attach(session.id), { code: "repository-not-approved" });
	assert.equal(h.pi.processes.length, started);
});

test("a Pi that exits while attach is still binding its topic is not reported as connected", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	h.pi.last.events.exited("killed");
	const send = h.telegram.sendMessage.bind(h.telegram);
	h.telegram.sendMessage = async (input) => {
		if (input.threadId === Number(session.topicId)) h.pi.last.events.exited("crashed on start");
		return send(input);
	};

	await assert.rejects(h.coordinator.attach(session.id), /crashed on start/);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);
	assert.equal((await h.coordinator.sessions())[0].sessions[1].status, "disconnected");
});

test("attach refuses a session another live Pi has open, locally and from the control topic, naming the process", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	h.pi.last.events.exited("killed");
	h.leases.held.set(session.piSessionId, [31337]);
	const started = h.pi.processes.length;

	await assert.rejects(h.coordinator.attach("fix-ci"), { code: "session-in-use", message: /fix-ci is open in another Pi \(process 31337\)/ });
	assert.match(await control(h, "/rc attach fix-ci"), /open in another Pi \(process 31337\)/);
	assert.equal(h.pi.processes.length, started);

	h.leases.held.set(session.piSessionId, [process.pid]);
	await assert.rejects(h.coordinator.attach("fix-ci"), { code: "session-in-use", message: /open in this Pi/ });

	// The lease adapter drops leases whose process is gone; with no live holder, attach takes over.
	h.leases.held.delete(session.piSessionId);
	assert.equal((await h.coordinator.attach("fix-ci")).alreadyConnected, false);
	assert.equal(h.pi.processes.length, started + 1);
});

test("/rc sessions tells sessions open in another Pi, or in this one, apart from disconnected ones", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const elsewhere = await h.coordinator.newSession({ name: "elsewhere", current });
	await h.coordinator.newSession({ name: "idle", current });
	for (const process of h.pi.processes) process.events.exited("killed");
	h.leases.held.set(elsewhere.session.piSessionId, [31337]);
	h.leases.held.set(current.id, [process.pid]);
	await h.coordinator.stop();

	const groups = await h.coordinator.sessions();
	assert.deepEqual(groups[0].sessions.map((session) => [session.name, session.status, session.openIn]), [
		["fix-flake", "open", [{ pid: process.pid, here: true }]],
		["elsewhere", "open", [{ pid: 31337, here: false }]],
		["idle", "disconnected", undefined],
	]);
	const text = renderSessions(groups);
	assert.match(text, /fix-flake · main · open in this Pi/);
	assert.match(text, /elsewhere · rc\/elsewhere · open in another Pi \(process 31337\)/);
	assert.match(text, /idle · rc\/idle · disconnected/);
});

test("a conversation that takes over a workspace's topic keeps the earlier one attachable", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const earlier = await startWith(h);
	await h.coordinator.stop();
	// A conversation that never got a response has no history to keep once it is replaced.
	const blank = Object.assign(new FakePiSession(), { id: "pi-blank", name: "", sessionFile: "/sessions/pi-blank.jsonl" });
	await startWith(h, blank);
	await h.coordinator.stop();
	const later = Object.assign(new FakePiSession(), { id: "pi-later", name: "retry", sessionFile: "/sessions/pi-later.jsonl" });
	h.pi.histories.add(later.sessionFile);
	await startWith(h, later);

	const [stored] = h.stores.sessions.items;
	assert.equal(stored.piSessionId, "pi-later");
	assert.deepEqual(stored.earlierConversations?.map((item) => [item.piSessionId, item.piSessionFile, item.name]), [
		["pi-current", "/sessions/pi-current.jsonl", "fix-flake"],
	]);
	assert.match(await control(h, "/rc sessions"), /retry · main · running[\s\S]*earlier: fix-flake · main · disconnected · \/rc attach pi-current/);

	// Two conversations never share a workspace: not while the later one is connected, nor while another Pi has it open.
	await assert.rejects(h.coordinator.attach("pi-current"), { code: "session-in-use", message: /retry.*connected/ });
	await h.coordinator.stop();
	await h.coordinator.start({});
	h.leases.held.set("pi-later", [31337]);
	await assert.rejects(h.coordinator.attach("pi-current"), { code: "session-in-use", message: /process 31337/ });
	h.leases.held.delete("pi-later");
	h.leases.held.set("pi-current", [31338]);
	await assert.rejects(h.coordinator.attach("pi-current"), { code: "session-in-use", message: /process 31338/ });
	h.leases.held.delete("pi-current");

	const { session } = await h.coordinator.attach("pi-current");
	assert.equal(h.pi.last.id, "pi-current");
	assert.equal(h.pi.last.sessionFile, "/sessions/pi-current.jsonl");
	assert.equal(session.id, earlier.session.id);
	assert.equal(session.piSessionId, "pi-current");
	assert.equal(session.name, "fix-flake");
	assert.equal(Number(session.topicId), earlier.topic, "the workspace keeps its topic");
	assert.deepEqual(h.telegram.renamed.at(-1), { threadId: earlier.topic, name: "demo / fix-flake / main" });
	assert.deepEqual(h.stores.sessions.items[0].earlierConversations?.map((item) => item.piSessionId), ["pi-later"]);
	assert.equal((await h.coordinator.attach("fix-flake")).alreadyConnected, true);
});

test("a rollback that cannot undo every step names what it left behind", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const send = h.telegram.sendMessage.bind(h.telegram);
	h.telegram.sendMessage = async (input) => {
		if (input.threadId !== undefined && input.threadId > 502) throw new Error("fetch failed");
		return send(input);
	};
	h.telegram.deleteForumTopic = async () => { throw new Error("not enough rights"); };
	const create = h.pi.create.bind(h.pi);
	h.pi.create = async (input, events) => {
		const agent = await create(input, events);
		h.pi.last.closeFailure = new Error("did not exit");
		return agent;
	};
	h.workspaces.removeFailure = new Error("could not remove worktree /work/demo.worktrees/rc-fix-ci or branch rc/fix-ci: locked");

	await assert.rejects(h.coordinator.newSession({ name: "fix-ci", current }), (error: Error & { code?: string; cause?: unknown }) => {
		assert.equal(error.code, "rollback-incomplete");
		assert.match(error.message, /^fetch failed/);
		assert.match(error.message, /session topic "demo \/ fix-ci \/ rc\/fix-ci" \(503\): not enough rights/);
		assert.match(error.message, /Pi process of fix-ci: did not exit/);
		assert.match(error.message, /could not remove worktree \/work\/demo\.worktrees\/rc-fix-ci or branch rc\/fix-ci: locked/);
		assert.equal((error.cause as Error).message, "fetch failed");
		return true;
	});
	assert.equal(h.stores.sessions.items.length, 1);
});

test("a session that never got a prompt can be attached, and is stale only once its written history is lost", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	assert.equal(await h.pi.hasHistory(session), false, "Pi writes no history before the first response");
	assert.equal(session.unprompted, true);
	h.pi.last.events.exited("killed");
	assert.equal((await h.coordinator.sessions())[0].sessions[1].status, "disconnected");

	const { session: attached } = await h.coordinator.attach("fix-ci");
	assert.equal(h.pi.last.id, session.piSessionId);
	assert.equal(attached.unprompted, true);

	await prompted(h, session);
	h.pi.last.events.exited("killed");
	assert.equal((await h.coordinator.sessions())[0].sessions[1].status, "disconnected");
	h.pi.histories.delete(session.piSessionFile!);
	assert.equal((await h.coordinator.sessions())[0].sessions[1].status, "stale");
	await assert.rejects(h.coordinator.attach("fix-ci"), { code: "stale-session" });
});

test("a session whose first run started is no longer unprompted, even if Pi dies before answering", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });

	h.pi.last.report({ type: "run-start", prompt: "go" });
	await until(() => h.stores.sessions.items.find((item) => item.id === session.id)?.unprompted === undefined);
	h.pi.last.events.exited("crashed");
	assert.equal((await h.coordinator.sessions())[0].sessions[1].status, "stale", "never restarted empty under its old id");
	await assert.rejects(h.coordinator.attach("fix-ci"), { code: "stale-session" });
});
