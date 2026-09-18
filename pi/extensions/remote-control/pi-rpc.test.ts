import assert from "node:assert/strict";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { AgentSession, PiActivity, Repository } from "./coordinator.ts";
import { RpcPiSessions } from "./pi-rpc.ts";
import { until } from "./test-support.ts";

/**
 * Stands in for `pi --mode rpc`: answers get_state/get_commands, runs a scripted
 * turn per prompt, asks one dialog, and exits when stdin closes.
 */
const FAKE_PI = String.raw`
const args = process.argv.slice(2);
const flag = (name) => { const i = args.indexOf(name); return i === -1 ? undefined : args[i + 1]; };
const file = flag("--session") ?? process.cwd() + "/new-session.jsonl";
const id = process.env.FAKE_PI_ID ?? file.split("/").pop().replace(".jsonl", "");
const log = (value) => process.stdout.write(JSON.stringify(value) + "\n");
const answers = [];
let buffer = "";
process.stdin.on("data", (chunk) => {
	buffer += chunk;
	let index;
	while ((index = buffer.indexOf("\n")) !== -1) {
		const command = JSON.parse(buffer.slice(0, index));
		buffer = buffer.slice(index + 1);
		handle(command);
	}
});
process.stdin.on("end", () => process.exit(0));
function handle(command) {
	const respond = (data, success = true, error) => log({ id: command.id, type: "response", command: command.type, success, data, error });
	switch (command.type) {
		case "get_state": return respond({ sessionId: id, sessionFile: file, sessionName: flag("--name"), cwd: process.cwd(), args });
		case "get_commands": return respond({ commands: [{ name: "merge-pr", source: "extension" }, { name: "skill:tdd", source: "skill" }] });
		case "extension_ui_response": answers.push(command); return;
		case "prompt": {
			if (command.message === "crash") { process.stderr.write("fatal: boom\n"); process.exit(3); }
			if (command.message === "reject") return respond(undefined, false, "busy compacting");
			respond();
			log({ type: "agent_start" });
			log({ type: "tool_execution_start", toolCallId: "t1", toolName: "bash", args: { command: "ls" } });
			log({ type: "tool_execution_end", toolCallId: "t1", toolName: "bash", isError: false, result: { content: [{ type: "text", text: "SECRET" }] } });
			log({ type: "extension_ui_request", id: "ui-1", method: "confirm", title: "Delete branch?" });
			setTimeout(() => {
				log({ type: "agent_end", messages: [{ role: "assistant", content: [{ type: "text", text: "answer " + command.message + " " + command.streamingBehavior + " " + JSON.stringify(answers) }] }] });
				log({ type: "agent_settled" });
			}, 20);
		}
	}
}
`;

async function setup(t: test.TestContext) {
	const root = await realpath(await mkdtemp(join(tmpdir(), "rc-rpc-")));
	t.after(() => rm(root, { recursive: true, force: true }));
	const script = join(root, "fake-pi.mjs");
	await writeFile(script, FAKE_PI);
	const sessions = new RpcPiSessions({ command: [process.execPath, script] });
	const activity: PiActivity[] = [];
	const exits: string[] = [];
	const events = { activity: (item: PiActivity) => activity.push(item), exited: (reason: string) => exits.push(reason) };
	const repository: Repository = { id: "repo", path: root, name: "demo", registeredAt: "" };
	return { root, sessions, activity, exits, events, repository };
}

test("starts a named Pi session in its workspace and relays its run, never tool output", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "fix ci", repository: h.repository, workspace: { path: h.root, branch: "rc/fix-ci", created: true } }, h.events);
	t.after(() => agent.close());
	assert.equal(agent.id, "new-session");
	assert.equal(agent.sessionFile, `${h.root}/new-session.jsonl`);
	assert.equal(agent.workspace, h.root);
	assert.equal(agent.branch, "rc/fix-ci");
	assert.equal(agent.isIdle(), true);

	agent.prompt("go");
	assert.equal(agent.isIdle(), false, "busy as soon as a prompt is sent");
	await until(() => h.activity.some((item) => item.type === "settled"), 3000);
	assert.equal(agent.isIdle(), true);
	assert.deepEqual(h.activity.map((item) => item.type), ["run-start", "tool-start", "tool-end", "notice", "response", "settled"]);
	assert.deepEqual(h.activity[0], { type: "run-start", prompt: "go" });
	assert.match((h.activity[3] as { text: string }).text, /Delete branch\?.*cancelled/);
	const response = h.activity[4] as { text: string };
	assert.match(response.text, /^answer go steer /);
	assert.match(response.text, /"id":"ui-1","cancelled":true/, "the dialog was answered, so Pi does not hang");
	assert.ok(!JSON.stringify(h.activity).includes("SECRET"));
});

test("follow-ups are queued after the run and extension commands are refused", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());

	agent.followUp("later");
	await until(() => h.activity.some((item) => item.type === "settled"), 3000);
	assert.match((h.activity.find((item) => item.type === "response") as { text: string }).text, /^answer later followUp/);

	h.activity.length = 0;
	agent.prompt("/merge-pr now");
	agent.steer("reject");
	await until(() => h.activity.length === 2, 3000);
	assert.match((h.activity[0] as { text: string }).text, /\/merge-pr.*not available remotely/);
	assert.match((h.activity[1] as { text: string }).text, /busy compacting/);
	assert.equal(agent.isIdle(), true);
});

test("resumes the persisted session file and refuses a different conversation", async (t) => {
	const h = await setup(t);
	const file = join(h.root, "abc.jsonl");
	await writeFile(file, "{}\n");
	const session = { piSessionId: "abc", piSessionFile: file, name: "x", workspace: h.root, branch: "rc/x", repositoryPath: h.root } as AgentSession;

	assert.equal(await h.sessions.hasHistory(session), true);
	assert.equal(await h.sessions.hasHistory({ ...session, piSessionFile: join(h.root, "gone.jsonl") }), false);
	assert.equal(await h.sessions.hasHistory({ ...session, piSessionFile: undefined }), false);

	const agent = await h.sessions.resume(session, h.events);
	t.after(() => agent.close());
	assert.equal(agent.id, "abc");
	assert.equal(agent.sessionFile, file);

	const mismatched = new RpcPiSessions({ command: [process.execPath, join(h.root, "fake-pi.mjs")], env: { FAKE_PI_ID: "other" } });
	await assert.rejects(mismatched.resume(session, h.events), /other.*instead of abc/);
});

test("reports a Pi process that exits on its own, but not one that was closed", async (t) => {
	const h = await setup(t);
	const workspace = { path: h.root, branch: "rc/x", created: true };
	const crashing = await h.sessions.create({ name: "x", repository: h.repository, workspace }, h.events);
	crashing.prompt("crash");
	await until(() => h.exits.length === 1, 3000);
	assert.match(h.exits[0], /exit code 3.*fatal: boom/);

	const closed = await h.sessions.create({ name: "y", repository: h.repository, workspace }, h.events);
	await closed.close();
	await new Promise((resolve) => setTimeout(resolve, 50));
	assert.equal(h.exits.length, 1);
});

test("a Pi that cannot start is reported with its error output", async (t) => {
	const h = await setup(t);
	const script = join(h.root, "broken.mjs");
	await writeFile(script, `process.stderr.write("No API key configured\\n"); process.exit(1);`);
	const broken = new RpcPiSessions({ command: [process.execPath, script] });
	await assert.rejects(
		broken.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events),
		/No API key configured/,
	);
	assert.deepEqual(h.exits, []);
});
