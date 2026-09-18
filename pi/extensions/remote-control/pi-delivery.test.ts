import assert from "node:assert/strict";
import test from "node:test";
import { PiDelivery } from "./pi-delivery.ts";
import { tick } from "./test-support.ts";

function harness(timeoutMs = 60_000) {
	const sent: [text: string, deliverAs: string][] = [];
	let idle = true;
	const delivery = new PiDelivery({
		send: (text, deliverAs) => { sent.push([text, deliverAs]); },
		isIdle: () => idle,
		timeoutMs,
	});
	return { delivery, sent, setIdle: (value: boolean) => { idle = value; } };
}

test("a second message waits until the first prompt's run has started, then steers it", () => {
	const h = harness();
	h.delivery.prompt("first");
	assert.equal(h.delivery.isReady(), false);
	h.delivery.prompt("second");
	h.delivery.followUp("later");
	assert.deepEqual(h.sent, [["first", "steer"]]);

	h.setIdle(false);
	h.delivery.runStarted();
	assert.deepEqual(h.sent, [["first", "steer"], ["second", "steer"], ["later", "followUp"]]);
	assert.equal(h.delivery.isReady(), true);
});

test("messages during compaction are held and delivered one run at a time afterwards", () => {
	const h = harness();
	h.setIdle(false);
	h.delivery.compactionStarted();
	h.delivery.steer("one");
	h.delivery.steer("two");
	assert.deepEqual(h.sent, []);

	h.setIdle(true);
	h.delivery.compactionEnded();
	assert.deepEqual(h.sent, [["one", "steer"]], "the first held message starts a run; the rest wait for it");
	h.setIdle(false);
	h.delivery.runStarted();
	assert.deepEqual(h.sent, [["one", "steer"], ["two", "steer"]]);
});

test("a prompt that never starts a run does not hold later messages forever", async () => {
	const h = harness(10);
	h.delivery.prompt("rejected by Pi");
	h.delivery.prompt("next");
	await tick(40);
	assert.deepEqual(h.sent, [["rejected by Pi", "steer"], ["next", "steer"]]);
});

test("dispose drops held messages and timers", async () => {
	const h = harness(10);
	h.delivery.prompt("first");
	h.delivery.prompt("dropped");
	h.delivery.dispose();
	await tick(40);
	assert.deepEqual(h.sent, [["first", "steer"]]);
});
