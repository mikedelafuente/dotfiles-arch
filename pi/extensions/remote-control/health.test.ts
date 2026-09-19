import assert from "node:assert/strict";
import test from "node:test";
import { CONTROL_TOPIC, GROUP, harness, OWNER, startWith, until, type Harness } from "./test-support.ts";

/** Sends an owner message in a topic and waits for the bridge's next reply there. */
async function ask(h: Harness, threadId: number, text: string): Promise<string> {
	const before = h.telegram.inTopic(threadId).length;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId, text });
	await until(() => h.telegram.inTopic(threadId).length > before, 2000);
	return h.telegram.inTopic(threadId).at(-1)!.text;
}

test("/rc status reports the bridge, each repository, and each session's agent and workspace", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const working = await h.coordinator.newSession({ name: "working", current });
	const exited = await h.coordinator.newSession({ name: "exited", current });
	const gone = await h.coordinator.newSession({ name: "gone", current });
	h.pi.processes.find((process) => process.id === working.session.piSessionId)!.idle = false;
	for (const { session } of [exited, gone]) h.pi.processes.find((process) => process.id === session.piSessionId)!.events.exited("killed");
	h.workspaces.branches.delete(gone.session.workspace);
	// A registered repository whose checkout was deleted, and a session whose repository was unregistered.
	await h.coordinator.registerRepository("/work/deleted");
	h.stores.sessions.items.push({ ...exited.session, id: "session-orphan", name: "orphan", repositoryPath: "/work/unlisted", workspace: "/work/unlisted" });

	const groups = await h.coordinator.sessions();
	assert.deepEqual(groups.map((group) => [group.repository.name, group.repository.approved, group.repository.exists]), [
		["demo", true, true],
		["unlisted", false, false],
	]);
	assert.deepEqual(groups[0].sessions.map((session) => [session.name, session.status, session.activity]), [
		["fix-flake", "active", "idle"],
		["working", "active", "working"],
		["exited", "disconnected", undefined],
		["gone", "missing-workspace", undefined],
	]);

	const reply = await ask(h, CONTROL_TOPIC, "/rc status");
	assert.match(reply, /remote control: running/i);
	assert.match(reply, /telegram: connected/i);
	assert.match(reply, /working · rc\/working · running, working/);
	assert.match(reply, /fix-flake · main · running, idle/);
	assert.match(reply, /exited · rc\/exited · disconnected/);
	assert.match(reply, /gone · rc\/gone · missing workspace/);
	assert.match(reply, /unlisted \(\/work\/unlisted\) · not approved · checkout missing/);
	assert.match(reply, /deleted \(\/work\/deleted\) · checkout missing/, "a registered repository without sessions is still reported");
});

test("/rc status in a session topic reports that session", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi, topic } = await startWith(h);
	pi.idle = false;

	const reply = await ask(h, topic, "/rc status");
	assert.match(reply, /remote control: running/i);
	assert.match(reply, /fix-flake · main · running, working/);
	assert.match(reply, /workspace: \/work\/demo/i);
	assert.doesNotMatch(reply, /other/);
	assert.equal(pi.delivered.length, 0, "not sent to Pi");
});

test("a Telegram outage never stops agents; once Telegram answers again, each topic gets one compact summary of what was held", async (t) => {
	const h = await harness({ retryDelayMs: 5, maxRetryDelayMs: 5 });
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	const agent = h.pi.last;
	const topic = Number(session.topicId);
	agent.report({ type: "run-start", prompt: "make the build green" });
	await until(() => h.telegram.inTopic(topic).some((message) => /working/i.test(message.text)));
	const progress = h.telegram.inTopic(topic).find((message) => /working/i.test(message.text))!;

	h.telegram.offline = true;
	await until(() => h.coordinator.status().unreachableSince !== undefined);
	agent.report({ type: "tool-start", toolCallId: "t1", toolName: "bash", args: { command: "npm test" } });
	agent.report({ type: "tool-end", toolCallId: "t1", isError: false });
	agent.report({ type: "response", text: "First answer." });
	agent.report({ type: "notice", text: "An extension warned about something." });
	agent.report({ type: "response", text: "All green." });
	agent.report({ type: "settled" });
	await until(() => h.coordinator.status().held === 3);
	const sent = h.telegram.inTopic(topic).length;
	assert.equal(agent.aborts, 0);
	assert.equal(agent.closed, false);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main", "demo / fix-ci / rc/fix-ci"], "topics stay routed");

	h.telegram.offline = false;
	// The long poll returns with the next update, which proves Telegram answers again.
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "back" });
	await until(() => h.telegram.inTopic(topic).length > sent);
	await until(() => h.coordinator.status().held === 0 && h.coordinator.status().unreachableSince === undefined);
	const summaries = h.telegram.inTopic(topic).slice(sent);
	assert.equal(summaries.length, 1, "one summary, not a replay");
	assert.match(summaries[0].text, /telegram was unreachable/i);
	assert.match(summaries[0].text, /kept running/i);
	assert.match(summaries[0].text, /now: idle/i);
	assert.match(summaries[0].text, /First answer\.[\s\S]*extension warned[\s\S]*All green\./);
	await until(() => h.telegram.edits.some((edit) => edit.messageId === progress.messageId && /done/i.test(edit.text)));
	assert.deepEqual(h.telegram.inTopic(Number((await h.coordinator.sessions())[0].sessions[0].topicId)).filter((message) => /unreachable/i.test(message.text)), [],
		"a topic with nothing held gets no summary");
});

test("a summary keeps only the latest held messages, and says how many it left out", async (t) => {
	const h = await harness({ retryDelayMs: 5, maxRetryDelayMs: 5 });
	t.after(() => h.coordinator.shutdown());
	const { pi, topic } = await startWith(h);
	h.telegram.offline = true;
	await until(() => h.coordinator.status().unreachableSince !== undefined);
	for (let index = 1; index <= 5; index++) h.coordinator.recordActivity(pi.id, { type: "response", text: `Answer ${index}.` });
	await until(() => h.coordinator.status().held === 5);
	const sent = h.telegram.inTopic(topic).length;

	h.telegram.offline = false;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "back" });
	await until(() => h.telegram.inTopic(topic).length > sent);
	const summary = h.telegram.inTopic(topic).at(-1)!.text;
	assert.match(summary, /2 earlier messages left out/i);
	assert.doesNotMatch(summary, /Answer 2\./);
	assert.match(summary, /Answer 3\.[\s\S]*Answer 4\.[\s\S]*Answer 5\./);
});

test("an agent that exits while Telegram is unreachable still gets its disconnect notice in the reconnect summary", async (t) => {
	const h = await harness({ retryDelayMs: 5, maxRetryDelayMs: 5 });
	t.after(() => h.coordinator.shutdown());
	const { pi: current } = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current });
	const topic = Number(session.topicId);
	h.telegram.offline = true;
	await until(() => h.coordinator.status().unreachableSince !== undefined);

	h.pi.last.report({ type: "response", text: "Half done." });
	h.pi.last.events.exited("was killed");
	await until(() => h.coordinator.status().held === 2);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);
	const sent = h.telegram.inTopic(topic).length;

	h.telegram.offline = false;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "back" });
	await until(() => h.telegram.inTopic(topic).length > sent);
	const summary = h.telegram.inTopic(topic).at(-1)!.text;
	assert.match(summary, /stopped being routed/);
	assert.match(summary, /Half done\.[\s\S]*Disconnected: the Pi agent was killed/);
	await until(() => h.coordinator.status().held === 0);
});
