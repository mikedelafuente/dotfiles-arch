import assert from "node:assert/strict";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import type { AgentSession } from "./coordinator.ts";
import { JsonAgentSessionStore, JsonCredentialStore, JsonStateStore } from "./state.ts";

test("credentials are private to the user and removed on clear", async (t) => {
	const root = await mkdtemp(join(tmpdir(), "rc-state-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const path = join(root, "pi-remote-control", "credentials.json");
	const store = new JsonCredentialStore(path);

	await store.write({ botToken: "secret" });
	assert.equal((await stat(path)).mode & 0o777, 0o600);
	assert.equal((await stat(join(root, "pi-remote-control"))).mode & 0o777, 0o700);
	assert.deepEqual(await store.read(), { botToken: "secret" });

	await store.clear();
	assert.equal(await store.read(), undefined);
	await store.clear();
});

test("agent sessions update in place but never share a workspace", async (t) => {
	const root = await mkdtemp(join(tmpdir(), "rc-state-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const store = new JsonAgentSessionStore(new JsonStateStore(join(root, "state.json")));
	const session = (id: string, workspace: string): AgentSession => ({
		id, name: id, repositoryId: "repo", repositoryPath: "/repo", workspace, branch: "main",
		piSessionId: `pi-${id}`, topicId: "1", topicName: id, createdAt: "2026-01-01T00:00:00Z", status: "active",
	});
	await store.save(session("one", "/one"));
	await store.save(session("two", "/two"));

	await store.update({ ...session("one", "/one"), piSessionId: "pi-later" });
	assert.equal((await store.get("one"))?.piSessionId, "pi-later");
	await assert.rejects(store.update(session("one", "/two")), { code: "duplicate-workspace" });
	await assert.rejects(store.update(session("missing", "/three")), { code: "session-not-found" });
	assert.equal((await store.list()).length, 2);
});
