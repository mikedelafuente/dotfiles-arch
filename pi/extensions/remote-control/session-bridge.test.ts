import assert from "node:assert/strict";
import test from "node:test";
import { RemoteControlCoordinator, type AuthorizedMessage, type LivePiSession, type RemoteControlAdapters } from "./coordinator.ts";
import { FakeTelegram, GROUP, memoryStores, OWNER, TOKEN, tick, until } from "./test-support.ts";

const CONTROL_TOPIC = 501;

/** The Pi conversation running in this process, recording what the bridge delivers to it. */
class FakePiSession implements LivePiSession {
	id = "pi-current";
	name = "fix-flake";
	workspace = "/work/demo";
	branch = "main";
	repositoryPath = "/work/demo";
	idle = true;
	delivered: [kind: "prompt" | "steer" | "followUp", text: string][] = [];
	isIdle(): boolean { return this.idle; }
	prompt(text: string): void { this.delivered.push(["prompt", text]); }
	steer(text: string): void { this.delivered.push(["steer", text]); }
	followUp(text: string): void { this.delivered.push(["followUp", text]); }
}

async function harness() {
	const telegram = new FakeTelegram();
	const stores = memoryStores();
	let stored: unknown;
	const adapters = {
		...stores,
		workspaces: {
			create: async (_repository, branch) => ({ path: `/tmp/${branch}`, branch, created: true }),
			adopt: async (path, branch = "main") => ({ path, branch, created: false }),
		},
		pi: { create: async () => ({ id: "pi" }) },
		telegram: { createSessionTopic: async () => ({ id: "topic" }) },
		credentials: { read: async () => stored, write: async (value: unknown) => { stored = structuredClone(value); }, clear: async () => { stored = undefined; } },
		telegramBot: () => telegram,
	} satisfies RemoteControlAdapters;
	let now = new Date("2026-01-01T00:00:00Z").getTime();
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date(now), { progressIntervalMs: 10 });
	await coordinator.login({
		token: TOKEN,
		onHandshakeCode: (code) => { setTimeout(() => telegram.push({ chat: GROUP, from: OWNER, text: code }), 5); },
	});
	assert.equal(telegram.topics.length, 1, "control topic");
	telegram.sent = [];
	return { telegram, stores, coordinator, advance: (ms: number) => { now += ms; } };
}

type Harness = Awaited<ReturnType<typeof harness>>;

async function startWith(h: Harness, pi = new FakePiSession(), onMessage?: (message: AuthorizedMessage) => Promise<void>) {
	const result = await h.coordinator.start({ session: pi, onMessage });
	assert.ok(result.session, "current Pi session exposed");
	return { pi, session: result.session, topic: Number(result.session.topicId) };
}

test("starting inside a repository registers it and exposes the current conversation in a named session topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { session, topic } = await startWith(h);

	assert.deepEqual(h.stores.repositories.items.map((repository) => [repository.path, repository.name]), [["/work/demo", "demo"]]);
	assert.equal(session.piSessionId, "pi-current");
	assert.equal(session.workspace, "/work/demo");
	assert.equal(session.branch, "main");
	assert.equal(session.topicName, "demo / fix-flake / main");
	assert.equal(h.telegram.topics.at(-1), "demo / fix-flake / main");
	assert.equal(h.stores.sessions.items.length, 1);
	assert.ok(h.telegram.inTopic(topic).some((message) => /connected/i.test(message.text)), "topic announces the connection");
});

test("restarting remote control reuses the approved repository and the session topic", async () => {
	const h = await harness();
	const first = await startWith(h);
	await h.coordinator.stop();
	const second = await startWith(h);
	await h.coordinator.stop();

	assert.equal(h.stores.repositories.items.length, 1);
	assert.equal(h.stores.sessions.items.length, 1);
	assert.equal(second.session.id, first.session.id);
	assert.equal(second.topic, first.topic);
	assert.equal(h.telegram.topics.length, 2, "control topic plus one session topic");
});

test("a new conversation in an already-exposed workspace takes over its topic, renamed for the current branch", async () => {
	const h = await harness();
	const earlier = await startWith(h);
	await h.coordinator.stop();

	const current = new FakePiSession();
	current.id = "pi-later";
	current.name = "";
	current.branch = "feat/x";
	const later = await startWith(h, current);
	await h.coordinator.stop();

	assert.equal(later.session.id, earlier.session.id);
	assert.equal(later.topic, earlier.topic);
	assert.equal(later.session.piSessionId, "pi-later");
	assert.equal(later.session.branch, "feat/x");
	assert.equal(later.session.name, "fix-flake", "an unnamed conversation keeps the topic's session name");
	assert.deepEqual(h.telegram.renamed, [{ threadId: earlier.topic, name: "demo / fix-flake / feat/x" }]);
	assert.equal(h.stores.sessions.items[0].piSessionId, "pi-later");
});

test("a session topic deleted in Telegram is replaced with a new one", async () => {
	const h = await harness();
	const earlier = await startWith(h);
	await h.coordinator.stop();
	h.telegram.deletedTopics.add(earlier.topic);

	const later = await startWith(h);
	await h.coordinator.stop();
	assert.notEqual(later.topic, earlier.topic);
	assert.equal(h.stores.sessions.items[0].topicId, String(later.topic));
});

test("topic messages become prompts when idle, steering while working, and follow-ups on request", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "fix the flaky test" });
	await until(() => pi.delivered.length === 1);
	pi.idle = false;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "use the retry helper" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc followup then open a PR" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc@pi_rc_bot followup and report back" });
	await until(() => pi.delivered.length === 4);

	assert.deepEqual(pi.delivered, [
		["prompt", "fix the flaky test"],
		["steer", "use the retry helper"],
		["followUp", "then open a PR"],
		["followUp", "and report back"],
	]);
	const acknowledgements = h.telegram.inTopic(topic).map((message) => message.text);
	assert.ok(acknowledgements.some((text) => /steer/i.test(text)));
	assert.ok(acknowledgements.some((text) => /follow-up/i.test(text)));
});

test("remote commands the session topic does not understand are explained instead of sent to Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	h.telegram.sent = [];

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc followup" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc teleport" });
	await until(() => h.telegram.inTopic(topic).length === 2);
	assert.deepEqual(pi.delivered, []);
	assert.match(h.telegram.inTopic(topic)[0].text, /\/rc followup <message>/);
	assert.match(h.telegram.inTopic(topic)[1].text, /\/rc followup <message>/);
});

test("messages in topics without a running session are not delivered anywhere", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const control: AuthorizedMessage[] = [];
	const { pi } = await startWith(h, new FakePiSession(), async (message) => { control.push(message); });
	h.telegram.sent = [];

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: 777, text: "anyone here?" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: 777, text: "hello?" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "control message" });
	await until(() => control.length === 1);
	assert.deepEqual(pi.delivered, []);
	assert.deepEqual(control.map((message) => message.text), ["control message"]);
	assert.equal(h.telegram.inTopic(777).length, 1, "one explanation per unknown topic");
	assert.match(h.telegram.inTopic(777)[0].text, /not connected/i);
});

test("active work is one editable progress message and the final response is delivered separately", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];

	h.coordinator.recordActivity("pi-current", { type: "run-start", prompt: "fix the flaky test" });
	await until(() => h.telegram.inTopic(topic).length === 1);
	const progress = h.telegram.inTopic(topic)[0];
	assert.match(progress.text, /working/i);
	assert.match(progress.text, /fix the flaky test/);

	h.coordinator.recordActivity("pi-current", { type: "tool-start", toolCallId: "1", toolName: "bash", args: { command: "npm test -- --grep flaky" } });
	h.coordinator.recordActivity("pi-current", { type: "tool-end", toolCallId: "1", isError: true });
	h.coordinator.recordActivity("pi-current", { type: "tool-start", toolCallId: "2", toolName: "edit", args: { path: "src/retry.ts", edits: ["…"] } });
	await until(() => h.telegram.edits.some((edit) => edit.text.includes("src/retry.ts")));
	h.coordinator.recordActivity("pi-current", { type: "tool-end", toolCallId: "2", isError: false });
	h.advance(65_000);
	h.coordinator.recordActivity("pi-current", { type: "response", text: "Fixed: the retry helper now waits for the socket." });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.edits.some((edit) => /done/i.test(edit.text)));
	await tick();

	assert.ok(h.telegram.edits.every((edit) => edit.messageId === progress.messageId), "progress is edited in place");
	assert.deepEqual(h.telegram.inTopic(topic).map((message) => message.text), [progress.text, "Fixed: the retry helper now waits for the socket."]);
	const final = h.telegram.edits.at(-1)!.text;
	assert.match(final, /done in 1m 5s/i);
	assert.match(final, /2 tool calls \(1 failed\)/);
	assert.match(h.telegram.edits.find((edit) => edit.text.includes("src/retry.ts"))!.text, /bash: npm test -- --grep flaky/);
});

test("the next run gets a fresh progress message", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	for (const prompt of ["one", "two"]) {
		h.coordinator.recordActivity("pi-current", { type: "run-start", prompt });
		h.coordinator.recordActivity("pi-current", { type: "response", text: `answer ${prompt}` });
		h.coordinator.recordActivity("pi-current", { type: "settled" });
	}
	await until(() => h.telegram.inTopic(topic).length === 4);
	await tick();
	const texts = h.telegram.inTopic(topic).map((message) => message.text);
	assert.match(texts[0], /one/);
	assert.equal(texts[1], "answer one");
	assert.match(texts[2], /two/);
	assert.equal(texts[3], "answer two");
});

test("long responses are condensed for Telegram and tool output is never sent", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];

	const secretOutput = "SECRET_TOOL_OUTPUT";
	const long = [`Summary: fixed it.`, ...Array.from({ length: 400 }, (_, i) => `Detail paragraph ${i} ${"x".repeat(40)}`), "TAIL_MARKER"].join("\n\n");
	h.coordinator.recordActivity("pi-current", { type: "run-start" });
	h.coordinator.recordActivity("pi-current", { type: "tool-start", toolCallId: "1", toolName: "bash", args: { command: `echo ${"y".repeat(500)}` } });
	h.coordinator.recordActivity("pi-current", { type: "tool-end", toolCallId: "1", isError: false });
	h.coordinator.recordActivity("pi-current", { type: "response", text: long });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.inTopic(topic).length === 2);
	await tick();

	const response = h.telegram.inTopic(topic)[1].text;
	assert.ok(response.length <= 4096, `response fits one Telegram message (${response.length})`);
	assert.ok(response.startsWith("Summary: fixed it."));
	assert.ok(response.endsWith("TAIL_MARKER"), "the conclusion is kept");
	assert.ok(!response.includes("Detail paragraph 200 "), "the middle is omitted");
	assert.match(response, /full response is in the Pi session/i);
	for (const text of [...h.telegram.sent.map((message) => message.text), ...h.telegram.edits.map((edit) => edit.text)]) {
		assert.ok(!text.includes(secretOutput));
		assert.ok(text.length <= 4096);
		assert.ok(!text.includes("y".repeat(200)), "tool arguments are shortened");
	}
});

test("failed and aborted runs are reported in the session topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	h.coordinator.recordActivity("pi-current", { type: "run-start" });
	h.coordinator.recordActivity("pi-current", { type: "response", text: "", error: "rate limited" });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.inTopic(topic).length === 2);
	assert.match(h.telegram.inTopic(topic)[1].text, /failed: rate limited/i);
});

test("activity is dropped when the bridge is stopped or the session is not exposed", async () => {
	const h = await harness();
	const { topic } = await startWith(h);
	h.coordinator.recordActivity("someone-else", { type: "run-start" });
	await tick();
	await h.coordinator.stop();
	h.telegram.sent = [];
	h.coordinator.recordActivity("pi-current", { type: "run-start" });
	await tick();
	assert.deepEqual(h.telegram.inTopic(topic), []);
});

test("stopping remote control tells the session topic it is disconnected", async () => {
	const h = await harness();
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	await h.coordinator.stop();
	assert.ok(h.telegram.inTopic(topic).some((message) => /disconnected/i.test(message.text)));
});

test("an error Pi retries is not reported as a failure", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	h.coordinator.recordActivity("pi-current", { type: "run-start", prompt: "go" });
	h.coordinator.recordActivity("pi-current", { type: "response", text: "", error: "overloaded" });
	h.coordinator.recordActivity("pi-current", { type: "run-start" });
	h.coordinator.recordActivity("pi-current", { type: "response", text: "All done." });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.edits.some((edit) => /done/i.test(edit.text)));
	await tick();
	assert.deepEqual(h.telegram.inTopic(topic).slice(1).map((message) => message.text), ["All done."]);
});

test("failure text is capped to one Telegram message", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	h.coordinator.recordActivity("pi-current", { type: "run-start" });
	h.coordinator.recordActivity("pi-current", { type: "response", text: "", error: "e".repeat(10_000) });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.inTopic(topic).length === 2);
	assert.ok(h.telegram.inTopic(topic)[1].text.length <= 4096);
	assert.match(h.telegram.inTopic(topic)[1].text, /^⚠️ Run failed: e+/);
});

test("a transient Telegram failure while rebinding fails the start instead of orphaning the topic", async () => {
	const h = await harness();
	const earlier = await startWith(h);
	await h.coordinator.stop();
	const send = h.telegram.sendMessage.bind(h.telegram);
	h.telegram.sendMessage = async (input) => {
		if (input.threadId === earlier.topic) throw Object.assign(new Error("fetch failed"), {});
		return send(input);
	};
	await assert.rejects(h.coordinator.start({ session: new FakePiSession() }), /fetch failed/);
	assert.equal(h.coordinator.status().running, false);
	assert.equal(h.telegram.topics.length, 2, "no replacement topic");
	assert.equal(h.stores.sessions.items[0].topicId, String(earlier.topic));
});

test("rate-limited topic updates are retried after Telegram's retry_after", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	h.telegram.sent = [];
	const send = h.telegram.sendMessage.bind(h.telegram);
	let limited = false;
	h.telegram.sendMessage = async (input) => {
		if (!limited && input.threadId === topic) {
			limited = true;
			throw Object.assign(new Error("Too Many Requests: retry after 0"), { errorCode: 429, retryAfter: 0 });
		}
		return send(input);
	};
	h.coordinator.recordActivity("pi-current", { type: "run-start", prompt: "go" });
	h.coordinator.recordActivity("pi-current", { type: "response", text: "answer" });
	h.coordinator.recordActivity("pi-current", { type: "settled" });
	await until(() => h.telegram.inTopic(topic).length === 2);
	await until(() => h.telegram.edits.some((edit) => /done/i.test(edit.text)));
});
