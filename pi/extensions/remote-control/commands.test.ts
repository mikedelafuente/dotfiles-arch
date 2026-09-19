import assert from "node:assert/strict";
import test from "node:test";
import type { PiCommand } from "./coordinator.ts";
import { CONTROL_TOPIC, GROUP, harness, OWNER, startWith, until, type Harness } from "./test-support.ts";

const DISCOVERED: PiCommand[] = [
	{ name: "merge-pr", description: "Merge this branch", source: "extension" },
	{ name: "fix-tests", description: "Fix failing tests", source: "prompt" },
	{ name: "skill:tdd", description: "Test-driven development", source: "skill" },
];

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
	for (const expected of ["/rc followup <message>", "/rc stop-agent", "/rc compact", "/rc thinking <level>", "/rc fix-tests", "Fix failing tests", "/rc skill:tdd"]) {
		assert.ok(listing.includes(expected), `lists ${expected}:\n${listing}`);
	}
	assert.match(listing, /local Pi only[^]*\/merge-pr/i, "extension commands are listed as local-only");
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

test("extension commands and unknown /rc commands are explained instead of sent to Pi", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.commandList = DISCOVERED;
	assert.match(await ask(h, topic, "/rc merge-pr"), /\/merge-pr.*local Pi/i);
	assert.match(await ask(h, topic, "/rc teleport"), /\/rc commands/);
	assert.deepEqual(pi.delivered, []);
});

test("Pi built-ins in the catalog run through the session, with their arguments checked", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);

	assert.equal(await ask(h, topic, "/rc compact keep the test plan"), "ran /compact");
	assert.match(await ask(h, topic, "/rc thinking loud"), /Usage: \/rc thinking <level>.*high/);
	assert.equal(await ask(h, topic, "/rc thinking high"), "ran /thinking");
	assert.deepEqual(pi.builtins, [["compact", "keep the test plan"], ["thinking", "high"]]);
	assert.deepEqual(pi.delivered, []);
});

test("a failing built-in is reported in the topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	const { pi, topic } = await startWith(h);
	pi.runBuiltin = async () => { throw new Error("Nothing to compact"); };
	assert.match(await ask(h, topic, "/rc compact"), /\/compact failed: Nothing to compact/);
});

test("starting remote control adds /rc to the group's Telegram command menu", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	await startWith(h);
	assert.deepEqual(h.telegram.menus.map((menu) => [menu.chatId, menu.commands.map((command) => command.command)]), [[GROUP.id, ["rc"]]]);
});

test("the control topic's /rc help names every control command", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.stop());
	await startWith(h);
	const help = await ask(h, CONTROL_TOPIC, "/rc help");
	for (const command of ["/rc sessions", "/rc new", "/rc attach", "/rc stop-agent"]) assert.ok(help.includes(command), `${command} in:\n${help}`);
});
