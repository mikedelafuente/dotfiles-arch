import assert from "node:assert/strict";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { JsonCredentialStore } from "./state.ts";

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
