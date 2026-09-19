/**
 * The extension against a fake ExtensionAPI: what its Pi event handlers and `/rc`
 * command do around a runtime swap. Credentials and state go to a temporary
 * directory, and the working directory is not a Git repository.
 */
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { rememberForReconnect, takeReconnect } from "./reconnect.ts";
import { tick, until } from "./test-support.ts";

type Handler = (event: any, ctx: any) => Promise<unknown>;
type Command = { handler: (args: string, ctx: any) => Promise<void>; getArgumentCompletions(prefix: string): { value: string }[] | null };

const root = await mkdtemp(join(tmpdir(), "rc-index-"));
process.env.XDG_CONFIG_HOME = join(root, "config");
process.env.XDG_STATE_HOME = join(root, "state");
const { default: remoteControlExtension } = await import("./index.ts");
test.after(() => rm(root, { recursive: true, force: true }));

/** Loads the extension, as Pi does for every runtime, into a fake API and context. */
function load() {
	const handlers = new Map<string, Handler[]>();
	const commands = new Map<string, Command>();
	const notified: [text: string, level: string][] = [];
	const calls: string[] = [];
	const pi = {
		on: (event: string, handler: Handler) => handlers.set(event, [...(handlers.get(event) ?? []), handler]),
		registerCommand: (name: string, command: Command) => commands.set(name, command),
	};
	const ctx = {
		cwd: root,
		hasUI: true,
		sessionManager: { getSessionId: () => "pi-local", getSessionFile: () => undefined },
		ui: { notify: (text: string, level: string) => notified.push([text, level]), setStatus: () => undefined },
		newSession: async () => { calls.push("newSession"); return { cancelled: false }; },
		reload: async () => { calls.push("reload"); },
	};
	remoteControlExtension(pi as never);
	const emit = async (event: string, payload: object) => {
		for (const handler of handlers.get(event) ?? []) await handler({ type: event, ...payload }, ctx);
	};
	return { emit, rc: commands.get("rc")!, ctx, notified, calls };
}

test("/new or a quit while remote control is stopped does not start it in the next runtime", async () => {
	for (const reason of ["new", "quit"]) {
		const before = load();
		await before.emit("session_shutdown", { reason });
		const after = load();
		await after.emit("session_start", { reason: reason === "quit" ? "startup" : reason });
		await tick();
		assert.deepEqual(after.notified.filter(([text]) => /Remote control/.test(text)), [], reason);
	}
});

test("a reconnect that fails is reported locally, and remote control stays off", async () => {
	for (const reason of ["new", "reload"] as const) {
		rememberForReconnect(globalThis, reason, true);
		const next = load();
		await next.emit("session_start", { reason });
		await until(() => next.notified.length > 0);
		assert.match(next.notified[0]![0], /Remote control did not start: .*not logged in/);
		assert.equal(next.notified[0]![1], "error");
		await next.rc.handler("status", next.ctx);
		assert.match(next.notified.at(-1)![0], /not logged in/);
		assert.equal(takeReconnect(globalThis, reason), false, "consumed");
	}
});

test("the unlisted replace-runtime subcommand runs Pi's /new and /reload", async () => {
	const { rc, ctx, calls } = load();
	assert.deepEqual(rc.getArgumentCompletions("re"), null, "not offered locally");
	await rc.handler("replace-runtime new", ctx);
	await rc.handler("replace-runtime reload", ctx);
	assert.deepEqual(calls, ["newSession", "reload"]);
});

test("local /rc archive and /rc cleanup explain their usage, and need a session to act on", async () => {
	const { rc, ctx, notified } = load();
	await rc.handler("cleanup workspace", ctx);
	assert.match(notified.at(-1)![0], /Usage: \/rc cleanup history <session>/);
	await rc.handler("archive", ctx);
	assert.match(notified.at(-1)![0], /Usage: \/rc archive <session>/);
	await rc.handler("cleanup history nobody", ctx);
	assert.match(notified.at(-1)![0], /\/rc cleanup failed: Agent session not found: nobody/);
});
