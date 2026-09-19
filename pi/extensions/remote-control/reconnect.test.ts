import assert from "node:assert/strict";
import test from "node:test";
import { rememberForReconnect, takeReconnect } from "./reconnect.ts";

test("remote control reconnects after /new and /reload only when its bridge was running", () => {
	for (const reason of ["new", "reload"] as const) {
		const store = {};
		rememberForReconnect(store, reason, true);
		assert.equal(takeReconnect(store, reason), true, reason);

		const stopped = {};
		rememberForReconnect(stopped, reason, false);
		assert.equal(takeReconnect(stopped, reason), false, `${reason} while stopped`);
	}
});

test("quit, resume, and fork never reconnect", () => {
	for (const [shutdown, start] of [["quit", "startup"], ["resume", "resume"], ["fork", "fork"]] as const) {
		const store = {};
		rememberForReconnect(store, shutdown, true);
		assert.equal(takeReconnect(store, start), false, shutdown);
	}
});

test("the reconnect is consumed once, and only by a start of the same reason", () => {
	const store = {};
	rememberForReconnect(store, "new", true);
	assert.equal(takeReconnect(store, "new"), true);
	assert.equal(takeReconnect(store, "new"), false, "consumed");

	rememberForReconnect(store, "reload", true);
	assert.equal(takeReconnect(store, "startup"), false, "another reason");
	assert.equal(takeReconnect(store, "reload"), false, "consumed by the start that did not match");
});

test("a later shutdown that must not reconnect clears an earlier one", () => {
	const store = {};
	rememberForReconnect(store, "new", true);
	rememberForReconnect(store, "quit", true);
	assert.equal(takeReconnect(store, "new"), false);
});

test("the flag survives a re-import of the module", async () => {
	const store = {};
	rememberForReconnect(store, "reload", true);
	const fresh = (await import(`./reconnect.ts?reimport=${Date.now()}`)) as typeof import("./reconnect.ts");
	assert.equal(fresh.takeReconnect(store, "reload"), true);
});
