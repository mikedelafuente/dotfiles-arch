import assert from "node:assert/strict";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { AgentSession, PiActivity, PiDialog, Repository } from "./coordinator.ts";
import { RpcPiSessions } from "./pi-rpc.ts";
import { until } from "./test-support.ts";

/**
 * Stands in for `pi --mode rpc`: answers get_state/get_commands, runs a scripted
 * turn per prompt, asks one dialog, and exits when stdin closes. The prompt
 * "reload", and this extension's "/rc reload", add an extension command and signal
 * it the way this extension does. Extension commands run without starting a turn.
 */
const FAKE_PI = String.raw`
import { writeFileSync } from "node:fs";
const args = process.argv.slice(2);
const flag = (name) => { const i = args.indexOf(name); return i === -1 ? undefined : args[i + 1]; };
// Like Pi, --session-id opens the project session with that id or creates a new one under it.
const file = flag("--session") ?? process.cwd() + "/" + (flag("--session-id") ? "fresh-" + flag("--session-id") : "new-session") + ".jsonl";
const id = process.env.FAKE_PI_ID ?? flag("--session-id") ?? file.split("/").pop().replace(".jsonl", "");
const log = (value) => process.stdout.write(JSON.stringify(value) + "\n");
const answers = [];
const received = [];
let commands = [{ name: "merge-pr", source: "extension" }, { name: "skill:tdd", source: "skill", description: "Test-driven development" }];
if (process.env.FAKE_PI_RC) commands.push({ name: "rc", source: "extension" });
let sessionId = id;
let sessionFile = file;
let sessionName = flag("--name");
let model = { provider: "anthropic", id: "claude-sonnet-5" };
const models = [model, { provider: "anthropic", id: "claude-opus-5" }];
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
		case "get_state":
			writeFileSync(process.cwd() + "/pid", String(process.pid));
			writeFileSync(process.cwd() + "/state.json", JSON.stringify({ args, agentFlag: process.env.PI_REMOTE_CONTROL_AGENT }));
			if (process.env.FAKE_PI_FAIL_STATE) return respond(undefined, false, "no model available");
			return respond({ sessionId, sessionFile, sessionName, model, thinkingLevel: "medium", cwd: process.cwd(), args });
		case "set_session_name": sessionName = command.name; return respond();
		case "get_session_stats":
			return respond({
				sessionId, sessionFile, userMessages: 2, assistantMessages: 3, toolCalls: 4, toolResults: 4, totalMessages: 9,
				tokens: { input: 100, output: 20, cacheRead: 300, cacheWrite: 0, total: 420 }, cost: 0.5,
				contextUsage: { tokens: 5000, contextWindow: 200000, percent: 2.5 },
			});
		case "get_available_models": return respond({ models });
		case "set_model": {
			const found = models.find((candidate) => candidate.provider === command.provider && candidate.id === command.modelId);
			if (!found) return respond(undefined, false, "Model not found: " + command.provider + "/" + command.modelId);
			model = found;
			return respond(found);
		}
		case "new_session":
			if (process.env.FAKE_PI_CANCEL_NEW) return respond({ cancelled: true });
			sessionId = id + "-next";
			sessionFile = process.cwd() + "/" + sessionId + ".jsonl";
			sessionName = undefined;
			return respond({ cancelled: false });
		case "get_commands": if (process.env.FAKE_PI_HANG_COMMANDS) return; return respond({ commands });
		case "extension_ui_response": answers.push(command); return;
		case "abort": case "compact": case "set_thinking_level":
			received.push(command);
			writeFileSync(process.cwd() + "/received.json", JSON.stringify(received));
			if (command.type === "set_thinking_level" && command.level === "loud") return respond(undefined, false, "Invalid thinking level");
			return respond(command.type === "compact" ? { tokensBefore: 120000, estimatedTokensAfter: 30000 } : undefined);
		case "prompt": {
			if (command.message.startsWith("/merge-pr")) {
				received.push(command);
				writeFileSync(process.cwd() + "/received.json", JSON.stringify(received));
				return respond();
			}
			if (command.message === "/rc reload") {
				commands = [...commands, { name: "deploy", source: "extension" }];
				log({ type: "extension_ui_request", id: "ui-reload", method: "setStatus", statusKey: "remote-control:commands", statusText: "reloaded" });
				return respond();
			}
			if (command.message === "reload") {
				commands = [...commands, { name: "deploy", source: "extension" }];
				respond();
				log({ type: "agent_start" });
				log({ type: "extension_ui_request", id: "ui-reload", method: "setStatus", statusKey: "remote-control:commands", statusText: "reloaded" });
				return log({ type: "agent_settled" });
			}
			if (command.message === "choose") {
				respond();
				log({ type: "extension_ui_request", id: "ui-2", method: "select", title: "Which base?", options: ["main", "release"] });
				log({ type: "extension_ui_request", id: "ui-3", method: "input", title: "Commit message?" });
				return;
			}
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
	const dialogs: PiDialog[] = [];
	const events = {
		activity: (item: PiActivity) => activity.push(item),
		exited: (reason: string) => exits.push(reason),
		confirm: async (dialog: PiDialog) => { dialogs.push(dialog); return true; },
		choose: async (dialog: PiDialog & { options: string[] }) => { dialogs.push(dialog); return dialog.options.at(-1); },
	};
	const repository: Repository = { id: "repo", path: root, name: "demo", registeredAt: "" };
	return { root, sessions, activity, exits, events, dialogs, repository };
}

test("starts a named Pi session in its workspace, marked as a remote-control agent, and relays its run, never tool output", async (t) => {
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
	assert.deepEqual(h.activity.map((item) => item.type), ["run-start", "tool-start", "tool-end", "response", "settled"]);
	assert.deepEqual(h.activity[0], { type: "run-start", prompt: "go" });
	const response = h.activity[3] as { text: string };
	assert.match(response.text, /^answer go steer /);
	assert.deepEqual(h.dialogs, [{ title: "Delete branch?" }]);
	assert.match(response.text, /"id":"ui-1","confirmed":true/, "the owner's answer reached Pi");
	assert.ok(!JSON.stringify(h.activity).includes("SECRET"));
	const state = JSON.parse(await readFile(join(h.root, "state.json"), "utf8")) as { agentFlag?: string };
	assert.equal(state.agentFlag, "1");
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
	assert.match((h.activity[0] as { text: string }).text, /\/merge-pr is an extension command.*\/rc merge-pr/);
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

test("deleting a conversation's history removes its session file, and reports one already gone", async (t) => {
	const h = await setup(t);
	const file = join(h.root, "abc.jsonl");
	await writeFile(file, "{}\n");
	const session = { piSessionId: "abc", piSessionFile: file, name: "x", workspace: h.root, branch: "rc/x", repositoryPath: h.root } as AgentSession;

	assert.equal(await h.sessions.deleteHistory(session), true);
	assert.equal(await h.sessions.hasHistory(session), false);
	assert.equal(await h.sessions.deleteHistory(session), false);
	assert.equal(await h.sessions.deleteHistory({ ...session, piSessionFile: undefined }), false);
});

test("an unprompted session without history restarts under its own id; a prompted one is refused", async (t) => {
	const h = await setup(t);
	const missing = join(h.root, "never-written.jsonl");
	const session = { piSessionId: "0199-abc", piSessionFile: missing, name: "fix ci", workspace: h.root, branch: "rc/x", repositoryPath: h.root } as AgentSession;

	await assert.rejects(h.sessions.resume(session, h.events), /history of fix ci was not found/);
	const agent = await h.sessions.resume({ ...session, unprompted: true }, h.events);
	t.after(() => agent.close());
	assert.equal(agent.id, "0199-abc");
	assert.equal(agent.sessionFile, join(h.root, "fresh-0199-abc.jsonl"));
	const state = JSON.parse(await readFile(join(h.root, "state.json"), "utf8")) as { args: string[] };
	assert.deepEqual(state.args, ["--mode", "rpc", "--session-id", "0199-abc", "--name", "fix ci"]);
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

test("a Pi that fails to report its state is stopped, not left running", async (t) => {
	const h = await setup(t);
	const failing = new RpcPiSessions({ command: [process.execPath, join(h.root, "fake-pi.mjs")], env: { FAKE_PI_FAIL_STATE: "1" } });
	await assert.rejects(
		failing.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events),
		/no model available/,
	);
	const pid = Number(await readFile(join(h.root, "pid"), "utf8"));
	await until(() => { try { process.kill(pid, 0); return false; } catch { return true; } }, 3000);
});

test("select dialogs are answered by the owner; text dialogs are still cancelled", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	agent.prompt("choose");
	await until(() => h.activity.some((item) => item.type === "notice"), 3000);
	assert.deepEqual(h.dialogs, [{ title: "Which base?", options: ["main", "release"] }]);
	assert.match((h.activity.find((item) => item.type === "notice") as { text: string }).text, /Commit message\?.*cancelled/);
});

test("discovered commands are refreshed after the agent's Pi reloads its resources", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	assert.deepEqual(await agent.commands(), [
		{ name: "merge-pr", source: "extension", description: undefined },
		{ name: "skill:tdd", source: "skill", description: "Test-driven development" },
	]);

	agent.prompt("reload");
	await until(() => h.activity.some((item) => item.type === "settled"), 3000);
	h.activity.length = 0;
	agent.prompt("/deploy now");
	await until(() => h.activity.some((item) => item.type === "notice"), 3000);
	assert.match((h.activity[0] as { text: string }).text, /\/deploy is an extension command/);
	assert.ok((await agent.commands()).some((command) => command.name === "deploy"));
});

test("abort and the catalog's built-ins are sent as their RPC commands", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	await agent.abort();
	assert.deepEqual(await agent.compact("keep the plan"), { tokensBefore: 120000, estimatedTokensAfter: 30000 });
	await agent.setThinkingLevel("high");
	await assert.rejects(agent.setThinkingLevel("loud" as "high"), /Invalid thinking level/);
	const received = JSON.parse(await readFile(join(h.root, "received.json"), "utf8")) as Record<string, unknown>[];
	assert.deepEqual(received.map(({ id: _id, ...command }) => command), [
		{ type: "abort" },
		{ type: "compact", customInstructions: "keep the plan" },
		{ type: "set_thinking_level", level: "high" },
		{ type: "set_thinking_level", level: "loud" },
	]);
});

test("a Pi that never lists its commands still starts and takes messages", async (t) => {
	const h = await setup(t);
	const hanging = new RpcPiSessions({ command: [process.execPath, join(h.root, "fake-pi.mjs")], env: { FAKE_PI_HANG_COMMANDS: "1" }, commandsTimeoutMs: 50 });
	const agent = await hanging.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	assert.deepEqual(await agent.commands(), []);
	agent.prompt("go");
	await until(() => h.activity.some((item) => item.type === "settled"), 3000);
});

test("renames, reports, and switches models through Pi's RPC commands", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	await agent.rename("parser");
	assert.equal(agent.name, "parser");
	assert.deepEqual(await agent.info(), {
		id: "new-session", file: `${h.root}/new-session.jsonl`, name: "parser", model: "anthropic/claude-sonnet-5", thinkingLevel: "medium",
		messages: { user: 2, assistant: 3, toolCalls: 4 },
		tokens: { input: 100, output: 20, cacheRead: 300, cacheWrite: 0 },
		cost: 0.5,
		context: { tokens: 5000, window: 200000, percent: 2.5 },
	});
	assert.deepEqual(await agent.models(), { current: "anthropic/claude-sonnet-5", available: ["anthropic/claude-sonnet-5", "anthropic/claude-opus-5"] });
	await agent.setModel("anthropic", "claude-opus-5");
	assert.equal((await agent.models()).current, "anthropic/claude-opus-5");
	await assert.rejects(agent.setModel("openai", "gpt-9"), /Model not found: openai\/gpt-9/);
});

test("/new moves the agent to the new conversation Pi started, unless an extension cancelled it", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	assert.deepEqual(await agent.newConversation!(), { id: "new-session-next", sessionFile: `${h.root}/new-session-next.jsonl` });
	assert.equal(agent.id, "new-session-next");
	assert.equal(agent.sessionFile, `${h.root}/new-session-next.jsonl`);

	const cancelling = new RpcPiSessions({ command: [process.execPath, join(h.root, "fake-pi.mjs")], env: { FAKE_PI_CANCEL_NEW: "1" } });
	const kept = await cancelling.create({ name: "y", repository: h.repository, workspace: { path: h.root, branch: "rc/y", created: true } }, h.events);
	t.after(() => kept.close());
	assert.equal(await kept.newConversation!(), undefined);
	assert.equal(kept.id, "new-session");
});

test("reload runs this extension's /rc reload in the agent's Pi and reports the commands it then discovers", async (t) => {
	const h = await setup(t);
	const withRc = new RpcPiSessions({ command: [process.execPath, join(h.root, "fake-pi.mjs")], env: { FAKE_PI_RC: "1" } });
	const agent = await withRc.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	await agent.reload!();
	await until(() => h.activity.some((item) => item.type === "commands-changed"), 3000);
	assert.ok((await agent.commands()).some((command) => command.name === "deploy"));

	const without = await h.sessions.create({ name: "y", repository: h.repository, workspace: { path: h.root, branch: "rc/y", created: true } }, h.events);
	t.after(() => without.close());
	await assert.rejects(without.reload!(), /does not run remote control's extension/);
});

test("an approved extension command is sent to Pi as a prompt, which runs it at once", async (t) => {
	const h = await setup(t);
	const agent = await h.sessions.create({ name: "x", repository: h.repository, workspace: { path: h.root, branch: "rc/x", created: true } }, h.events);
	t.after(() => agent.close());
	await agent.runExtensionCommand("/merge-pr --squash");
	const received = JSON.parse(await readFile(join(h.root, "received.json"), "utf8")) as Record<string, unknown>[];
	assert.deepEqual(received.map(({ id: _id, ...command }) => command), [{ type: "prompt", message: "/merge-pr --squash" }]);
	assert.equal(agent.isIdle(), true, "an extension command starts no run of its own");
});
