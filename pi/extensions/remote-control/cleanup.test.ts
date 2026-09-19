import assert from "node:assert/strict";
import test from "node:test";
import type { AgentSession, ConfirmCleanup } from "./coordinator.ts";
import { CONTROL_TOPIC, GROUP, harness, OWNER, startWith, until, type Harness, type SentMessage } from "./test-support.ts";

/** Starts remote control and one agent session from the main line that has answered once, so its Pi history exists. */
async function withAgent(h: Harness, name = "fix-ci") {
	const current = await startWith(h);
	const { session } = await h.coordinator.newSession({ name, current: current.pi });
	const agent = h.pi.last;
	agent.report({ type: "run-start", prompt: "hi" });
	agent.report({ type: "response", text: "hello" });
	agent.report({ type: "settled" });
	await until(() => h.stores.sessions.items.find((item) => item.id === session.id)?.unprompted === undefined);
	return { current, agent, session, topic: Number(session.topicId) };
}

/** Confirms every question, recording it and the label of the button that would confirm it. */
function confirmAll(asked: [question: string, action: string][] = []): ConfirmCleanup {
	return async (question, action) => { asked.push([question, action]); return true; };
}

const decline: ConfirmCleanup = async () => false;

function stored(h: Harness, session: AgentSession): AgentSession | undefined {
	return h.stores.sessions.items.find((item) => item.id === session.id);
}

function say(h: Harness, threadId: number, text: string): void {
	h.telegram.push({ chat: GROUP, from: OWNER, threadId, text });
}

async function buttonsIn(h: Harness, threadId: number, after = 0): Promise<SentMessage> {
	const find = () => h.telegram.inTopic(threadId).slice(after).findLast((message) => message.buttons?.length);
	await until(() => find() !== undefined);
	return find()!;
}

test("/rc archive closes an idle agent's topic and stops its Pi, keeping its history, workspace, and branch; attach brings it back", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, session, topic } = await withAgent(h);

	say(h, CONTROL_TOPIC, "/rc archive fix-ci");
	const question = await buttonsIn(h, CONTROL_TOPIC);
	assert.match(question.text, /archive fix-ci/i);
	assert.match(question.text, /kept/i);
	const sent = h.telegram.inTopic(CONTROL_TOPIC).length;
	h.telegram.press(question, "Archive");
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).length > sent);
	const report = h.telegram.inTopic(CONTROL_TOPIC).at(-1)!.text;
	assert.match(report, /archived fix-ci/i);
	assert.match(report, /closed.*topic/i);
	assert.match(report, /kept.*Pi history.*workspace \/work\/demo\.worktrees\/rc-fix-ci.*branch rc\/fix-ci/is);

	assert.ok(h.telegram.closedTopics.has(topic));
	assert.ok(h.telegram.inTopic(topic).some((message) => /archived/i.test(message.text)), "the topic says why it closed");
	assert.equal(agent.closed, true);
	assert.ok(h.pi.histories.has(session.piSessionFile!));
	assert.ok(h.workspaces.branches.has(session.workspace));
	assert.deepEqual(h.workspaces.removed, []);
	assert.deepEqual(h.telegram.deleted, []);
	assert.ok(stored(h, session)?.archivedAt);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);
	const [group] = await h.coordinator.sessions();
	assert.equal(group.sessions.find((item) => item.id === session.id)?.status, "disconnected");
	const listed = h.telegram.inTopic(CONTROL_TOPIC).length;
	say(h, CONTROL_TOPIC, "/rc sessions");
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).length > listed);
	assert.match(h.telegram.inTopic(CONTROL_TOPIC).at(-1)!.text, /archived: fix-ci · rc\/fix-ci · disconnected/i);

	const { session: attached } = await h.coordinator.attach("fix-ci");
	assert.equal(attached.topicId, session.topicId, "the same topic, reopened");
	assert.ok(!h.telegram.closedTopics.has(topic));
	assert.equal(stored(h, session)?.archivedAt, undefined);
	assert.equal(h.pi.last.id, session.piSessionId);
});

test("archive refuses a working agent and does nothing unless confirmed", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, session, topic } = await withAgent(h);

	agent.idle = false;
	await assert.rejects(h.coordinator.archive("fix-ci", confirmAll()), { code: "session-busy" });
	agent.idle = true;
	assert.equal(await h.coordinator.archive("fix-ci", decline), undefined);
	assert.ok(!h.telegram.closedTopics.has(topic));
	assert.equal(agent.closed, false);
	assert.equal(stored(h, session)?.archivedAt, undefined);

	say(h, CONTROL_TOPIC, "/rc archive fix-ci");
	h.telegram.press(await buttonsIn(h, CONTROL_TOPIC), "Cancel");
	await until(() => h.telegram.edits.some((edit) => /cancelled/i.test(edit.text)));
	assert.ok(!h.telegram.closedTopics.has(topic));
});

test("a confirmation applies only to the session state it asked about", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { agent, topic } = await withAgent(h);

	const busyWhileAsked: ConfirmCleanup = async () => { agent.idle = false; return true; };
	await assert.rejects(h.coordinator.archive("fix-ci", busyWhileAsked), { code: "session-busy" });
	assert.ok(!h.telegram.closedTopics.has(topic));
	assert.equal(agent.closed, false);
});

test("/rc archive in a session topic archives the current conversation's topic; the local Pi keeps its conversation", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { pi, session, topic } = await startWith(h);

	say(h, topic, "/rc archive");
	h.telegram.press(await buttonsIn(h, topic), "Archive");
	await until(() => h.telegram.closedTopics.has(topic));
	assert.deepEqual(h.coordinator.status().topics, []);
	assert.equal(h.coordinator.isRemoteControlled(pi.id), false);
	assert.ok(stored(h, session)?.archivedAt);

	// Starting /rc again in that workspace is an explicit request to expose it: the topic reopens.
	await h.coordinator.stop();
	await startWith(h, pi);
	assert.ok(!h.telegram.closedTopics.has(topic));
	assert.equal(stored(h, session)?.archivedAt, undefined);
	assert.deepEqual(h.coordinator.status().topics, ["demo / fix-flake / main"]);
});

test("history cleanup deletes only a disconnected session's Pi history, after confirmation, and reports each file", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { session, topic } = await withAgent(h);
	const earlier = { piSessionId: "pi-earlier", piSessionFile: "/sessions/pi-earlier.jsonl", name: "fix-ci", branch: "rc/fix-ci", replacedAt: "2026-01-01T00:00:00Z" };
	stored(h, session)!.earlierConversations = [earlier];
	h.pi.histories.add(earlier.piSessionFile);

	await assert.rejects(h.coordinator.cleanupHistory("fix-ci", confirmAll()), { code: "session-busy" });
	await h.coordinator.archive("fix-ci", confirmAll());
	h.leases.held.set("pi-earlier", [4242]);
	await assert.rejects(h.coordinator.cleanupHistory("fix-ci", confirmAll()), { code: "session-in-use" });
	h.leases.held.clear();
	assert.equal(await h.coordinator.cleanupHistory("fix-ci", decline), undefined);
	assert.deepEqual(h.pi.deletedHistories, []);

	const asked: [string, string][] = [];
	const report = await h.coordinator.cleanupHistory("fix-ci", confirmAll(asked));
	assert.match(asked[0][0], new RegExp(`${session.piSessionFile}[\\s\\S]*pi-earlier\\.jsonl[\\s\\S]*cannot be undone`));
	assert.equal(asked[0][1], "Delete history");
	assert.deepEqual(h.pi.deletedHistories, [session.piSessionFile, earlier.piSessionFile]);
	assert.deepEqual(report?.done, [`Pi history ${session.piSessionFile}`, `Pi history ${earlier.piSessionFile}`]);
	assert.deepEqual(report?.failed, []);
	assert.ok(h.workspaces.branches.has(session.workspace), "the workspace is kept");
	assert.deepEqual(h.telegram.deleted, [], "the topic is kept");
	assert.ok(h.telegram.closedTopics.has(topic));
	assert.equal(stored(h, session)?.earlierConversations, undefined);
	const [group] = await h.coordinator.sessions();
	assert.equal(group.sessions.find((item) => item.id === session.id)?.status, "stale");

	const again = await h.coordinator.cleanupHistory("fix-ci", confirmAll(asked));
	assert.deepEqual(again?.done, []);
	assert.equal(asked.length, 1, "nothing to delete: nothing asked");
});

test("workspace cleanup removes a clean, merged workspace and its branch, keeping the Pi history and topic", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { session } = await withAgent(h);

	await assert.rejects(h.coordinator.cleanupWorkspace("fix-ci", {}, confirmAll()), { code: "session-busy" });
	await h.coordinator.archive("fix-ci", confirmAll());
	h.workspaces.branchStates.set("rc/fix-ci", { mainLine: "main", merged: true, pullRequest: 12, unmergedCommits: 2 });

	const asked: [string, string][] = [];
	const report = await h.coordinator.cleanupWorkspace("fix-ci", {}, confirmAll(asked));
	assert.match(asked[0][0], /worktree \/work\/demo\.worktrees\/rc-fix-ci/);
	assert.match(asked[0][0], /branch rc\/fix-ci.*merged into main.*#12/);
	assert.equal(asked[0][1], "Remove");
	assert.deepEqual(h.workspaces.removals, [{ path: session.workspace, branch: "rc/fix-ci", discardChanges: false }]);
	assert.deepEqual(report?.done, ["worktree /work/demo.worktrees/rc-fix-ci", "branch rc/fix-ci"]);
	assert.match(report!.kept.join("; "), /Pi history/);
	assert.ok(h.pi.histories.has(session.piSessionFile!));
	const [group] = await h.coordinator.sessions();
	assert.equal(group.sessions.find((item) => item.id === session.id)?.status, "missing-workspace");
});

test("workspace cleanup refuses uncommitted work or an unmerged branch until abandoned or forced, and reports what force discarded", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { session } = await withAgent(h);
	await h.coordinator.archive("fix-ci", confirmAll());
	h.workspaces.branchStates.set("rc/fix-ci", { mainLine: "main", merged: false, unmergedCommits: 3 });
	h.workspaces.dirty.set(session.workspace, [" M src/app.ts", "?? notes.txt"]);

	await assert.rejects(h.coordinator.cleanupWorkspace("fix-ci", {}, confirmAll()), (error: Error & { code?: string }) =>
		error.code === "workspace-not-clean" && /src\/app\.ts/.test(error.message) && /--force/.test(error.message));
	await assert.rejects(h.coordinator.cleanupWorkspace("fix-ci", { abandon: true }, confirmAll()), { code: "workspace-not-clean" });
	h.workspaces.dirty.delete(session.workspace);
	await assert.rejects(h.coordinator.cleanupWorkspace("fix-ci", {}, confirmAll()), (error: Error & { code?: string }) =>
		error.code === "branch-not-merged" && /3 commits/.test(error.message) && /--abandon/.test(error.message));
	assert.deepEqual(h.workspaces.removals, []);

	const asked: [string, string][] = [];
	assert.equal(await h.coordinator.cleanupWorkspace("fix-ci", { abandon: true }, async (question, action) => { asked.push([question, action]); return false; }), undefined);
	assert.match(asked[0][0], /not merged.*3 commits/);
	assert.equal(asked[0][1], "Abandon and remove");
	assert.deepEqual(h.workspaces.removals, []);

	h.workspaces.dirty.set(session.workspace, [" M src/app.ts", "?? notes.txt"]);
	const report = await h.coordinator.cleanupWorkspace("fix-ci", { force: true }, confirmAll(asked));
	assert.match(asked[1][0], /discards 2 uncommitted changes[\s\S]*src\/app\.ts[\s\S]*notes\.txt/);
	assert.equal(asked[1][1], "Force remove");
	assert.deepEqual(h.workspaces.removals, [{ path: session.workspace, branch: "rc/fix-ci", discardChanges: true }]);
	assert.deepEqual(report?.done, [
		"worktree /work/demo.worktrees/rc-fix-ci",
		"branch rc/fix-ci, with 3 commits not merged into main",
		"2 uncommitted changes: M src/app.ts, ?? notes.txt",
	]);
});

test("workspace cleanup from the control topic asks with buttons and reports what was removed", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { session } = await withAgent(h);
	await h.coordinator.archive("fix-ci", confirmAll());
	h.workspaces.dirty.set(session.workspace, ["?? scratch.txt"]);

	say(h, CONTROL_TOPIC, "/rc cleanup workspace fix-ci");
	await until(() => /uncommitted/i.test(h.telegram.inTopic(CONTROL_TOPIC).at(-1)?.text ?? ""));
	assert.deepEqual(h.workspaces.removals, []);

	const before = h.telegram.inTopic(CONTROL_TOPIC).length;
	say(h, CONTROL_TOPIC, "/rc cleanup workspace fix-ci --force");
	const question = await buttonsIn(h, CONTROL_TOPIC, before);
	assert.match(question.text, /scratch\.txt/);
	const sent = h.telegram.inTopic(CONTROL_TOPIC).length;
	h.telegram.press(question, "Force remove");
	await until(() => h.telegram.inTopic(CONTROL_TOPIC).length > sent);
	const report = h.telegram.inTopic(CONTROL_TOPIC).at(-1)!.text;
	assert.match(report, /done:[\s\S]*worktree \/work\/demo\.worktrees\/rc-fix-ci[\s\S]*branch rc\/fix-ci[\s\S]*scratch\.txt/i);
	assert.match(report, /kept:[\s\S]*Pi history/i);
});

test("workspace cleanup never removes a repository's main checkout", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	await startWith(h);
	await h.coordinator.archive("fix-flake", confirmAll());
	await assert.rejects(h.coordinator.cleanupWorkspace("fix-flake", { force: true }, confirmAll()), { code: "main-checkout" });
	assert.deepEqual(h.workspaces.removals, []);
});

test("a session whose topic is archived, history deleted, and workspace removed is forgotten", async (t) => {
	const h = await harness();
	t.after(() => h.coordinator.shutdown());
	const { session } = await withAgent(h);

	await h.coordinator.archive("fix-ci", confirmAll());
	const history = await h.coordinator.cleanupHistory("fix-ci", confirmAll());
	assert.equal(history?.forgotten, false);
	const workspace = await h.coordinator.cleanupWorkspace("fix-ci", {}, confirmAll());
	assert.equal(workspace?.forgotten, true);
	assert.equal(stored(h, session), undefined);
	assert.deepEqual((await h.coordinator.sessions()).flatMap((group) => group.sessions.map((item) => item.name)), ["fix-flake"]);
});
