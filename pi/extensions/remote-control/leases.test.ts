import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { SessionLeaseFiles } from "./leases.ts";

async function leaseDirectory(t: test.TestContext): Promise<string> {
	const root = await mkdtemp(join(tmpdir(), "rc-leases-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	return join(root, "leases");
}

/** A real process that stays alive until the test kills it. */
function sleeper(t: test.TestContext) {
	const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
	const exited = new Promise((resolve) => child.once("exit", resolve));
	t.after(() => { child.kill("SIGKILL"); return exited; });
	return { pid: child.pid!, kill: async () => { child.kill("SIGKILL"); await exited; } };
}

test("a Pi leases its conversation while it runs and releases it on shutdown", async (t) => {
	const directory = await leaseDirectory(t);
	const leases = new SessionLeaseFiles(directory);

	assert.deepEqual(await leases.holders("0199-abc"), []);
	await leases.acquire("0199-abc");
	await leases.acquire("0199-abc");
	assert.deepEqual(await leases.holders("0199-abc"), [process.pid]);
	assert.deepEqual(await leases.holders("0199-other"), []);

	await leases.release("0199-abc");
	assert.deepEqual(await leases.holders("0199-abc"), []);
	await leases.release("0199-abc");
});

test("every live Pi holding a conversation is reported, and releasing one keeps the others", async (t) => {
	const directory = await leaseDirectory(t);
	const other = sleeper(t);
	await new SessionLeaseFiles(directory, other.pid).acquire("shared");
	const mine = new SessionLeaseFiles(directory);
	await mine.acquire("shared");

	assert.deepEqual(await mine.holders("shared"), [process.pid, other.pid].sort((a, b) => a - b));
	await mine.release("shared");
	assert.deepEqual(await mine.holders("shared"), [other.pid]);
});

test("a lease whose process is gone is stale: it is removed and not reported", async (t) => {
	const directory = await leaseDirectory(t);
	const crashed = sleeper(t);
	await new SessionLeaseFiles(directory, crashed.pid).acquire("abc");
	await crashed.kill();

	const leases = new SessionLeaseFiles(directory);
	assert.deepEqual(await leases.holders("abc"), []);
	assert.deepEqual(await readdir(directory).then((entries) => Promise.all(entries.map((entry) => readdir(join(directory, entry))))), [[]]);
});

test("a lease naming a live process that started after it was written is stale, not a holder", async (t) => {
	const directory = await leaseDirectory(t);
	const leases = new SessionLeaseFiles(directory);
	await leases.acquire("abc");
	// Simulate PID reuse: the lease records a different start than the process now using that PID.
	const [entry] = await readdir(directory);
	await writeFile(join(directory, entry, String(process.pid)), JSON.stringify({ pid: process.pid, startTime: "1" }));

	assert.deepEqual(await leases.holders("abc"), []);
});

test("conversation ids never escape the lease directory", async (t) => {
	const directory = await leaseDirectory(t);
	const leases = new SessionLeaseFiles(directory);
	await leases.acquire("../escape");
	await leases.acquire("..");
	assert.deepEqual(await leases.holders("../escape"), [process.pid]);
	assert.deepEqual(await leases.holders(".."), [process.pid]);
	assert.equal((await readdir(directory)).length, 2);
	assert.deepEqual(await readdir(join(directory, "..")).then((entries) => entries.filter((name) => name !== "leases")), []);
});

test("unreadable lease entries are ignored rather than trusted", async (t) => {
	const directory = await leaseDirectory(t);
	const leases = new SessionLeaseFiles(directory);
	await leases.acquire("abc");
	const [entry] = await readdir(directory);
	await writeFile(join(directory, entry, "garbage"), "not json");
	await mkdir(join(directory, entry, "nested"));
	assert.deepEqual(await leases.holders("abc"), [process.pid]);
});
