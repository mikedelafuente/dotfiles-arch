import assert from "node:assert/strict";
import test from "node:test";
import { CONTROL_TOPIC, FakePiSession, GROUP, harness, OWNER, STRANGER, startWith, until, type Harness, type SentMessage } from "./test-support.ts";

/** Starts remote control and one agent session from the main line; returns the agent and its topic. */
async function withAgent(h: Harness) {
	const current = await startWith(h);
	const { session } = await h.coordinator.newSession({ name: "fix-ci", current: current.pi });
	return { current, agent: h.pi.last, session, topic: Number(session.topicId) };
}

/** The latest message in a topic that carries inline buttons. */
async function buttonsIn(h: Harness, threadId: number): Promise<SentMessage> {
	await until(() => h.telegram.inTopic(threadId).some((message) => message.buttons?.length));
	return h.telegram.inTopic(threadId).findLast((message) => message.buttons?.length)!;
}

async function answered(h: Harness, callbackId: string): Promise<string> {
	await until(() => h.telegram.answerTo(callbackId) !== undefined);
	return h.telegram.answerTo(callbackId)!.text ?? "";
}

/** Sends an owner message in a topic. */
function say(h: Harness, threadId: number, text: string): void {
	h.telegram.push({ chat: GROUP, from: OWNER, threadId, text });
}

test("an agent's confirmation dialog becomes a single-use Telegram approval in its session topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);

	const answer = agent.events.confirm({ title: "Approve merge?", message: "gh pr merge 12 --squash" });
	const approval = await buttonsIn(h, topic);
	assert.match(approval.text, /Approve merge\?/);
	assert.match(approval.text, /gh pr merge 12 --squash/);
	assert.match(approval.text, /fix-ci/, "names the agent session");

	const first = h.telegram.press(approval, "Approve");
	assert.equal(await answer, true);
	assert.match(await answered(h, first), /approved/i);
	await until(() => h.telegram.edits.some((edit) => edit.messageId === approval.messageId));
	const edit = h.telegram.edits.findLast((candidate) => candidate.messageId === approval.messageId)!;
	assert.match(edit.text, /approved/i);
	assert.ok(!edit.buttons?.length, "the buttons are removed");

	const replay = h.telegram.press(approval, "Approve");
	assert.match(await answered(h, replay), /no longer valid/i);
});

test("a denied confirmation resolves false", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Delete branch rc/old?" });
	h.telegram.press(await buttonsIn(h, topic), "Deny");
	assert.equal(await answer, false);
});

test("approvals are bound to the owner and to the topic they were asked in", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic, current } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve deployment?" });
	const approval = await buttonsIn(h, topic);

	const stranger = h.telegram.press(approval, "Approve", STRANGER);
	assert.match(await answered(h, stranger), /not authorized/i);
	const elsewhere = h.telegram.press(approval, "Approve", OWNER, current.topic);
	assert.match(await answered(h, elsewhere), /no longer valid/i);
	const inControl = h.telegram.press(approval, "Approve", OWNER, CONTROL_TOPIC);
	assert.match(await answered(h, inControl), /no longer valid/i);

	h.telegram.press(approval, "Deny");
	assert.equal(await answer, false, "the rejected presses did not use it up");
});

test("an approval pressed after it expired is refused and counts as a denial", async (t) => {
	const h = await harness({ approvalTimeoutMs: 60_000 });
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve merge?" });
	const approval = await buttonsIn(h, topic);
	h.advance(60_001);
	const late = h.telegram.press(approval, "Approve");
	assert.match(await answered(h, late), /expired/i);
	assert.equal(await answer, false);
});

test("an unanswered approval expires on its own, denied", async (t) => {
	const h = await harness({ approvalTimeoutMs: 30 });
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve merge?" });
	const approval = await buttonsIn(h, topic);
	assert.equal(await answer, false);
	await until(() => h.telegram.edits.some((edit) => edit.messageId === approval.messageId && /expired/i.test(edit.text)));
});

test("stopping remote control denies pending approvals", async () => {
	const h = await harness();
	const { agent, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve merge?" });
	await buttonsIn(h, topic);
	await h.coordinator.stop();
	assert.equal(await answer, false);
	await h.coordinator.shutdown();
});

test("an agent's select dialog offers its options as buttons", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);
	const choice = agent.events.choose({ title: "Which base branch?", options: ["main", "release"] });
	const question = await buttonsIn(h, topic);
	assert.match(question.text, /Which base branch\?/);
	h.telegram.press(question, "release");
	assert.equal(await choice, "release");

	const cancelled = agent.events.choose({ title: "Which remote?", options: ["origin", "upstream"] });
	h.telegram.press(await buttonsIn(h, topic), "Cancel");
	assert.equal(await cancelled, undefined);
});

test("the current conversation's approvals are asked in its topic and can be withdrawn", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { topic } = await startWith(h);

	const approved = h.coordinator.requestApproval("pi-current", { title: "Approve merge?", message: "git merge feature" });
	h.telegram.press(await buttonsIn(h, topic), "Approve");
	assert.equal(await approved, true);

	const withdraw = new AbortController();
	const withdrawn = h.coordinator.requestApproval("pi-current", { title: "Approve privileged command?", message: "sudo pacman -Syu" }, withdraw.signal);
	const approval = await buttonsIn(h, topic);
	withdraw.abort();
	assert.equal(await withdrawn, undefined, "withdrawn: the owner decided nothing");
	const late = h.telegram.press(approval, "Approve");
	assert.match(await answered(h, late), /no longer valid/i);

	assert.equal(await h.coordinator.requestApproval("someone-else", { title: "Approve merge?" }), undefined, "no topic routes that conversation");
});

test("an approval that cannot be posted leaves the decision to the local Pi, but denies an agent's request", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic, current } = await withAgent(h);
	const send = h.telegram.sendMessage.bind(h.telegram);
	h.telegram.sendMessage = async (input) => {
		if (input.buttons) throw new Error("fetch failed");
		return send(input);
	};
	assert.equal(await h.coordinator.requestApproval(current.pi.id, { title: "Approve merge?" }), undefined);
	assert.equal(await agent.events.confirm({ title: "Approve merge?" }), false);
	assert.ok(!h.telegram.inTopic(topic).some((message) => message.buttons));
});

test("a stop confirmed after its run ended does not stop the next run", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi, topic } = await startWith(h);
	pi.idle = false;
	h.coordinator.recordActivity(pi.id, { type: "run-start", prompt: "first" });
	say(h, topic, "/rc stop-agent");
	const confirmation = await buttonsIn(h, topic);

	h.coordinator.recordActivity(pi.id, { type: "response", text: "done" });
	h.coordinator.recordActivity(pi.id, { type: "settled" });
	h.coordinator.recordActivity(pi.id, { type: "run-start", prompt: "second" });
	const press = h.telegram.press(confirmation, "Stop run");
	assert.match(await answered(h, press), /no longer valid/i);
	assert.equal(pi.aborts, 0);
});

test("/rc stop-agent in a session topic aborts the run only after confirmation", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi, topic } = await startWith(h);

	say(h, topic, "/rc stop-agent");
	await until(() => h.telegram.inTopic(topic).some((message) => /not running/i.test(message.text)));
	assert.equal(pi.aborts, 0);

	pi.idle = false;
	say(h, topic, "/rc stop-agent");
	h.telegram.press(await buttonsIn(h, topic), "Keep running");
	await until(() => h.telegram.answers.length === 1);
	assert.equal(pi.aborts, 0, "a declined stop does nothing");

	say(h, topic, "/rc stop-agent");
	await until(() => h.telegram.inTopic(topic).filter((message) => message.buttons?.length).length === 2);
	h.telegram.press(await buttonsIn(h, topic), "Stop run");
	await until(() => pi.aborts === 1);
	await until(() => h.telegram.inTopic(topic).some((message) => /stopped the current run/i.test(message.text)));
	assert.deepEqual(pi.delivered, [], "the command never reaches Pi as a prompt");
});

test("/rc stop-agent in the control topic selects a running agent, then confirms", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, current } = await withAgent(h);
	agent.idle = false;

	say(h, CONTROL_TOPIC, "/rc stop-agent");
	const selection = await buttonsIn(h, CONTROL_TOPIC);
	assert.deepEqual(selection.buttons!.flat().map((button) => button.text).sort(), ["Cancel", "fix-ci", "fix-flake"]);
	h.telegram.press(selection, "fix-ci");

	await until(() => h.telegram.inTopic(CONTROL_TOPIC).filter((message) => message.buttons?.length).length === 2);
	const confirmation = await buttonsIn(h, CONTROL_TOPIC);
	assert.match(confirmation.text, /fix-ci/);
	h.telegram.press(confirmation, "Stop run");
	await until(() => agent.aborts === 1);
	assert.equal(current.pi.aborts, 0);

	const stale = h.telegram.press(selection, "fix-flake");
	assert.match(await answered(h, stale), /no longer valid/i, "a selection is single-use");
});

test("/rc stop-agent <session> in the control topic confirms before aborting", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent } = await withAgent(h);
	agent.idle = false;
	say(h, CONTROL_TOPIC, "/rc stop-agent fix-ci");
	const confirmation = await buttonsIn(h, CONTROL_TOPIC);
	assert.equal(agent.aborts, 0);
	h.telegram.press(confirmation, "Stop run");
	await until(() => agent.aborts === 1);
});

test("/rc attach without a session offers the attachable ones", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, session } = await withAgent(h);
	agent.events.exited("was killed (SIGKILL)");
	await until(() => h.coordinator.status().topics.length === 1);

	say(h, CONTROL_TOPIC, "/rc attach");
	const selection = await buttonsIn(h, CONTROL_TOPIC);
	assert.deepEqual(selection.buttons!.flat().map((button) => button.text), ["fix-ci", "Cancel"]);
	h.telegram.press(selection, "fix-ci");
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).some((message) => /reconnected fix-ci/i.test(message.text)));
	assert.equal(h.pi.last.id, session.piSessionId);
});

test("/rc new with only a name offers the approved repositories", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	await startWith(h);

	say(h, CONTROL_TOPIC, "/rc new fix-docs");
	const selection = await buttonsIn(h, CONTROL_TOPIC);
	assert.match(selection.text, /fix-docs/);
	h.telegram.press(selection, "demo");
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).some((message) => /started fix-docs/i.test(message.text)));
	assert.deepEqual(h.workspaces.created.map((workspace) => workspace.branch), ["rc/fix-docs"]);
});

test("button presses from outside the approved group are refused", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve merge?" });
	const approval = await buttonsIn(h, topic);
	const forged = h.telegram.press({ ...approval, chatId: -999 }, "Approve");
	assert.match(await answered(h, forged), /no longer valid|not authorized/i);
	h.telegram.press(approval, "Deny");
	assert.equal(await answer, false);
});

test("a rebound topic invalidates approvals asked by the conversation it replaced", async () => {
	const h = await harness();
	const { topic } = await startWith(h);
	const answer = h.coordinator.requestApproval("pi-current", { title: "Approve merge?" });
	const approval = await buttonsIn(h, topic);
	await h.coordinator.stop();
	assert.equal(await answer, undefined, "remote control stopped: the local Pi decides");

	const later = new FakePiSession();
	later.id = "pi-later";
	await startWith(h, later);
	const stale = h.telegram.press(approval, "Approve");
	assert.match(await answered(h, stale), /no longer valid/i);
	await h.coordinator.shutdown();
});
