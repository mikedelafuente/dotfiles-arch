import assert from "node:assert/strict";
import test from "node:test";
import type { PiCommand } from "./coordinator.ts";
import { CONTROL_TOPIC, FakePiSession, GROUP, harness, OWNER, startWith, until, type Harness, type SentMessage } from "./test-support.ts";

const DISCOVERED: PiCommand[] = [
	{ name: "merge-pr", description: "Merge this branch", source: "extension" },
	{ name: "fix-tests", description: "Fix failing tests", source: "prompt" },
	{ name: "skill:tdd", description: "Test-driven development", source: "skill" },
];

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

/** The command names of the latest Telegram menu. */
function menu(h: Harness): string[] {
	return h.telegram.menus.at(-1)?.commands.map((command) => command.command) ?? [];
}

/** Sends an owner message in a topic and returns the bot's next reply there. */
async function ask(h: Harness, threadId: number, text: string): Promise<string> {
	const before = h.telegram.inTopic(threadId).length;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId, text });
	await until(() => h.telegram.inTopic(threadId).length > before);
	return h.telegram.inTopic(threadId).at(-1)!.text;
}

test("/rc commands lists remote-control commands, runnable Pi built-ins, and the conversation's discovered commands", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;

	const listing = await ask(h, topic, "/rc commands");
	for (const expected of [
		"/rc followup <message>", "/rc stop-agent", "/rc compact", "/rc thinking <level>", "/rc model [provider/model]", "/rc name <name>",
		"/rc session", "/rc new", "/rc reload", "/rc fix-tests", "Fix failing tests", "/rc skill:tdd",
	]) {
		assert.ok(listing.includes(expected), `lists ${expected}:\n${listing}`);
	}
	assert.match(listing, /after you approve[^]*\/rc merge-pr/i, "extension commands are listed as needing approval");
	assert.equal(await ask(h, topic, "/rc help"), listing);
});

test("discovery follows Pi's current commands, so a reload is reflected", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	assert.ok(!(await ask(h, topic, "/rc commands")).includes("/rc review"));
	pi.commandList = [...DISCOVERED, { name: "review", description: "Review the diff", source: "prompt" }];
	assert.ok((await ask(h, topic, "/rc commands")).includes("/rc review"));
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc review the parser" });
	await until(() => pi.delivered.length === 1);
	assert.deepEqual(pi.delivered, [["prompt", "/review the parser"]]);
});

test("/rc <discovered command> reaches Pi as that command, in order with other messages", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	pi.idle = false;

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc skill:tdd write the parser test" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "and keep it small" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc followup /fix-tests" });
	await until(() => pi.delivered.length === 3);
	assert.deepEqual(pi.delivered, [
		["steer", "/skill:tdd write the parser test"],
		["steer", "and keep it small"],
		["followUp", "/fix-tests"],
	]);
});

test("unknown /rc commands are explained instead of sent to Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	assert.match(await ask(h, topic, "/rc teleport"), /\/rc commands/);
	assert.deepEqual(pi.delivered, []);
});

test("an extension command runs only once the owner approves it, and never while the approval is open", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc merge-pr --squash" });
	const approval = await buttonsIn(h, topic);
	assert.match(approval.text, /\/merge-pr --squash/);
	assert.match(approval.text, /outside remote control's approvals/i, "says what approving it means");
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "meanwhile, check the logs" });
	await until(() => pi.delivered.length === 1);
	assert.deepEqual(pi.extensionCommands, [], "nothing runs before the owner approves");

	h.telegram.press(approval, "Approve");
	await until(() => pi.extensionCommands.length === 1);
	assert.deepEqual(pi.extensionCommands, ["/merge-pr --squash"]);

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/merge-pr" });
	await until(() => h.telegram.inTopic(topic).filter((message) => message.buttons?.length).length === 2);
	const second = await buttonsIn(h, topic);
	h.telegram.press(second, "Deny");
	await until(() => h.telegram.edits.some((edit) => edit.messageId === second.messageId));
	assert.deepEqual(pi.extensionCommands, ["/merge-pr --squash"], "a denied command does not run");
});

test("remote control's own /rc command is never run as an extension command", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = [...DISCOVERED, { name: "rc", description: "Telegram remote control", source: "extension" }];
	assert.match(await ask(h, topic, "/rc rc logout"), /cannot be run from Telegram/i);
	assert.ok(!menu(h).includes("rc_logout"));
	assert.deepEqual(pi.extensionCommands, []);
});

test("Pi built-ins in the catalog run through the session, with their arguments checked", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);

	assert.equal(await ask(h, topic, "/rc compact keep the test plan"), "Compacted the context from 1000 to about 200 tokens.");
	assert.match(await ask(h, topic, "/rc thinking loud"), /Usage: \/rc thinking <level>.*high/);
	assert.equal(await ask(h, topic, "/rc thinking high"), "Thinking level set to high.");
	assert.deepEqual(pi.builtins, [["compact", "keep the test plan"], ["thinking", "high"]]);
	assert.deepEqual(pi.delivered, []);
});

test("a failing built-in is reported in the topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.compact = async () => { throw new Error("Nothing to compact"); };
	assert.match(await ask(h, topic, "/rc compact"), /\/compact failed: Nothing to compact/);
});

test("a conversation that does not list its commands in time does not hold up the topic", async (t) => {
	const h = await harness({ commandTimeoutMs: 30 });
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commands = () => new Promise(() => undefined);
	assert.match(await ask(h, topic, "/rc commands"), /did not list its commands in time/);
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "carry on" });
	await until(() => pi.delivered.length === 1);
	assert.deepEqual(pi.delivered, [["prompt", "carry on"]]);
});

test("the group's Telegram command menu lists every command, with names Telegram accepts", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const pi = new FakePiSession();
	pi.commandList = [...DISCOVERED, { name: "Fix_Tests", description: "Collides once mapped", source: "prompt" }];
	await startWith(h, pi);
	await until(() => h.telegram.menus.length > 0);
	assert.equal(h.telegram.menus.length, 1, "set once, not once per route");
	assert.equal(h.telegram.menus[0].chatId, GROUP.id);
	assert.deepEqual(menu(h), [
		"rc", "commands", "followup", "stop_agent", "compact", "thinking", "model", "name", "session", "new", "reload",
		"merge_pr", "fix_tests", "skill_tdd",
	]);
	for (const command of h.telegram.menus[0].commands) {
		assert.match(command.command, /^[a-z0-9_]{1,32}$/);
		assert.ok(command.description.length >= 1 && command.description.length <= 256, command.command);
	}
});

test("a command picked from the Telegram menu runs as the command it stands for", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/skill_tdd@pi_rc_bot write the parser test" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/fix_tests" });
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/tmp/build.log is empty, why?" });
	await until(() => pi.delivered.length === 3);
	assert.deepEqual(pi.delivered, [["prompt", "/skill:tdd write the parser test"], ["prompt", "/fix-tests"], ["prompt", "/tmp/build.log is empty, why?"]]);
	assert.equal(await ask(h, topic, "/thinking@pi_rc_bot high"), "Thinking level set to high.");
	assert.match(await ask(h, topic, "/commands"), /Commands in this topic/);
});

test("the Telegram menu follows the commands of every connected conversation, including after a reload", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent } = await withAgent(h);
	await until(() => h.telegram.menus.length > 0);
	assert.ok(!menu(h).includes("deploy"));

	agent.commandList = [{ name: "deploy", description: "Deploy the branch", source: "extension" }];
	agent.report({ type: "commands-changed" });
	await until(() => menu(h).includes("deploy"));
	const menus = h.telegram.menus.length;
	agent.report({ type: "commands-changed" });
	await new Promise((resolve) => setTimeout(resolve, 30));
	assert.equal(h.telegram.menus.length, menus, "an unchanged menu is not set again");
});

test("the control topic's /rc help names every control command", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	await startWith(h);
	const help = await ask(h, CONTROL_TOPIC, "/rc help");
	for (const command of ["/rc sessions", "/rc new", "/rc attach", "/rc stop-agent"]) assert.ok(help.includes(command), `${command} in:\n${help}`);
});

test("/rc name renames the conversation, its agent session, and its topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, session, topic } = await withAgent(h);
	const answer = agent.events.confirm({ title: "Approve merge?" });
	const approval = await buttonsIn(h, topic);

	assert.match(await ask(h, topic, "/rc name"), /Usage: \/rc name <name>/);
	assert.match(await ask(h, topic, "/rc name parser rewrite"), /Renamed to parser rewrite/);
	assert.deepEqual(agent.renamedTo, ["parser rewrite"]);
	const stored = h.stores.sessions.items.find((item) => item.id === session.id)!;
	assert.equal(stored.name, "parser rewrite");
	assert.equal(stored.topicName, "demo / parser rewrite / rc/fix-ci");
	assert.deepEqual(h.telegram.renamed.at(-1), { threadId: topic, name: "demo / parser rewrite / rc/fix-ci" });
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main", "demo / parser rewrite / rc/fix-ci"]);

	h.telegram.press(approval, "Approve");
	assert.equal(await answer, true, "renaming does not withdraw an open approval");
});

test("/rc session reports the conversation's info and usage", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { topic } = await startWith(h);
	const info = await ask(h, topic, "/rc session");
	for (const expected of ["fix-flake", "pi-current", "/sessions/pi-current.jsonl", "anthropic/claude-sonnet-5", "3 user", "5 tool calls", "$0.0421", "9%"]) {
		assert.ok(info.includes(expected), `${expected} in:\n${info}`);
	}
});

test("/rc model lists the models, or sets one given as provider/model", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	const listing = await ask(h, topic, "/rc model");
	assert.match(listing, /Model: anthropic\/claude-sonnet-5/);
	assert.match(listing, /anthropic\/claude-opus-5/);
	assert.match(await ask(h, topic, "/rc model opus"), /Usage: \/rc model <provider\/model>/);
	assert.equal(await ask(h, topic, "/rc model anthropic/claude-opus-5"), "Model set to anthropic/claude-opus-5.");
	assert.match(await ask(h, topic, "/rc model openai/gpt-9"), /\/model failed: Model not found/);
	assert.deepEqual(pi.builtins, [["model", "anthropic/claude-opus-5"]]);
});

test("/rc new starts a new conversation in an agent's workspace and rebinds its topic; the previous one stays attachable", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, session, topic } = await withAgent(h);
	agent.report({ type: "response", text: "done" }); // The first response writes the history.
	const stop = h.coordinator.requestApproval(agent.id, { title: "Approve merge?" });
	await buttonsIn(h, topic);

	assert.match(await ask(h, topic, "/rc new"), /new conversation[^]*\/rc attach pi-new-1/i);
	assert.equal(await stop, undefined, "the replaced conversation's approvals no longer apply");
	const stored = h.stores.sessions.items.find((item) => item.id === session.id)!;
	assert.equal(stored.piSessionId, "pi-new-1-next");
	assert.equal(stored.unprompted, true);
	assert.equal(stored.name, "fix-ci");
	assert.equal(stored.topicId, String(topic));
	assert.deepEqual(stored.earlierConversations?.map((conversation) => conversation.piSessionId), ["pi-new-1"]);
	assert.deepEqual(agent.renamedTo, ["fix-ci"], "the new conversation carries the session's name");

	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "start over" });
	await until(() => agent.delivered.length === 1);
	agent.report({ type: "run-start", prompt: "start over" });
	await until(() => h.telegram.inTopic(topic).some((message) => message.text.includes("start over")));
});

test("/rc reload reloads an agent's Pi; the current conversation's /new and /reload stay local", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic, current } = await withAgent(h);
	assert.match(await ask(h, topic, "/rc reload"), /Reloaded/);
	assert.equal(agent.reloads, 1);

	for (const name of ["new", "reload"]) {
		assert.match(await ask(h, current.topic, `/rc ${name}`), new RegExp(`/${name}[^]*locally[^]*stops remote control`, "i"));
	}
	assert.equal(h.stores.sessions.items.find((item) => item.id === current.session.id)!.piSessionId, "pi-current");
});

test("a session command picked from the menu in the control topic is pointed at the session topics", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const notified: string[] = [];
	const pi = new FakePiSession();
	pi.commandList = DISCOVERED;
	await startWith(h, pi, async (message) => { notified.push(message.text); });
	await until(() => menu(h).includes("skill_tdd"));
	assert.match(await ask(h, CONTROL_TOPIC, "/compact@pi_rc_bot"), /session topic[^]*\/rc help/i);
	assert.match(await ask(h, CONTROL_TOPIC, "/skill_tdd"), /session topic/i);
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: CONTROL_TOPIC, text: "hello" });
	await until(() => notified.length === 1);
	assert.deepEqual(notified, ["hello"]);
});

test("/rc name refuses the name of another session in the same repository", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { current, agent, topic } = await withAgent(h);
	assert.match(await ask(h, topic, `/rc name ${current.session.name.toUpperCase()}`), /\/name failed: .*already has an agent session named fix-flake/);
	assert.deepEqual(agent.renamedTo, []);
});

test("an extension command gone by the time the owner approves it is not sent to Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	h.telegram.push({ chat: GROUP, from: OWNER, threadId: topic, text: "/rc merge-pr" });
	const approval = await buttonsIn(h, topic);
	pi.commandList = DISCOVERED.filter((command) => command.name !== "merge-pr");
	h.telegram.press(approval, "Approve");
	await until(() => h.telegram.inTopic(topic).some((message) => /no longer has \/merge-pr/.test(message.text)));
	assert.deepEqual(pi.extensionCommands, []);
	assert.deepEqual(pi.delivered, []);
});
