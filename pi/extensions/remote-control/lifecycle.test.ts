import assert from "node:assert/strict";
import test from "node:test";
import { RemoteControlCoordinator, type AuthorizedMessage, type RemoteControlAdapters, type TelegramChat, type TelegramUser } from "./coordinator.ts";
import { apiError, BOT, FakeLeases, FakePiSessions, FakeTelegram, FakeWorkspaces, GROUP, OWNER, STRANGER, TOKEN, until } from "./test-support.ts";

const ANONYMOUS_ADMIN: TelegramUser = { id: 1087968824, isBot: true, username: "GroupAnonymousBot" };

function harness() {
	const telegram = new FakeTelegram();
	let stored: unknown;
	let corrupt = false;
	const tokens: string[] = [];
	const adapters = {
		repositories: { getByPath: async () => undefined, list: async () => [], register: async () => undefined, remove: async () => undefined },
		sessions: { list: async () => [], get: async () => undefined, save: async () => undefined, update: async () => undefined, remove: async () => undefined },
		workspaces: new FakeWorkspaces(),
		pi: new FakePiSessions(),
		leases: new FakeLeases(),
		credentials: {
			read: async () => { if (corrupt) throw new SyntaxError("Unexpected token in JSON"); return stored; },
			write: async (value: unknown) => { stored = structuredClone(value); },
			clear: async () => { stored = undefined; corrupt = false; },
		},
		telegramBot: (token: string) => { tokens.push(token); return telegram; },
	} satisfies RemoteControlAdapters;
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date("2026-01-01T00:00:00Z"));
	return { telegram, coordinator, tokens, stored: () => stored, corruptCredentials: () => { corrupt = true; } };
}

/** Starts a login and sends the handshake code from `from` in `chat` once it is shown locally. */
function loginWith(h: ReturnType<typeof harness>, from: TelegramUser = OWNER, chat: TelegramChat = GROUP, timeoutMs = 2000) {
	return h.coordinator.login({
		token: TOKEN,
		timeoutMs,
		onHandshakeCode: (code) => {
			setTimeout(() => {
				h.telegram.push({ chat, from: STRANGER, text: "hello" });
				h.telegram.push({ chat, from, text: `/rc_login ${code}` });
			}, 5);
		},
	});
}

test("login rejects malformed and Telegram-rejected tokens without storing credentials", async () => {
	const h = harness();
	const noCode = () => assert.fail("handshake must not start");
	await assert.rejects(h.coordinator.login({ token: "not-a-token", onHandshakeCode: noCode }), { code: "invalid-token" });
	h.telegram.tokenValid = false;
	await assert.rejects(h.coordinator.login({ token: TOKEN, onHandshakeCode: noCode }), { code: "invalid-token" });
	assert.equal(h.stored(), undefined);
});

test("login captures the owner through the handshake code and stores machine-local credentials", async () => {
	const h = harness();
	h.telegram.push({ chat: GROUP, from: STRANGER, text: "stale message before login" });
	const credentials = await loginWith(h);
	assert.equal(credentials.owner.id, OWNER.id);
	assert.equal(credentials.bot.id, BOT.id);
	assert.equal(credentials.group.id, GROUP.id);
	assert.equal(h.telegram.topics.length, 1, "control topic created to prove topic permissions");
	assert.equal(credentials.group.controlTopicId, 501);
	assert.ok(h.telegram.sent.some((message) => message.threadId === 501), "bot proved it can post");
	assert.deepEqual(h.stored(), credentials);
	assert.equal((h.stored() as { botToken: string }).botToken, TOKEN);
});

test("re-login to the same group reuses the control topic", async () => {
	const h = harness();
	await loginWith(h);
	await loginWith(h);
	assert.equal(h.telegram.topics.length, 1);
});

test("login rejects groups that are not private forum groups with the required bot permissions", async () => {
	const cases: [string, (h: ReturnType<typeof harness>) => TelegramChat][] = [
		["direct message", () => ({ id: OWNER.id, type: "private" })],
		["group without topics", (h) => (h.telegram.chat = { ...GROUP, isForum: false })],
		["public group", (h) => (h.telegram.chat = { ...GROUP, username: "public_pi" })],
		["bot is not an administrator", (h) => { h.telegram.members.set(BOT.id, { status: "member" }); return GROUP; }],
		["bot cannot manage topics", (h) => { h.telegram.members.set(BOT.id, { status: "administrator", canManageTopics: false }); return GROUP; }],
		["owner is not a group administrator", (h) => { h.telegram.members.set(OWNER.id, { status: "member" }); return GROUP; }],
	];
	for (const [name, arrange] of cases) {
		const h = harness();
		const chat = arrange(h);
		await assert.rejects(loginWith(h, OWNER, chat), { code: "invalid-group" }, name);
		assert.equal(h.stored(), undefined, name);
	}
});

test("login fails clearly when no handshake arrives in time", async () => {
	const h = harness();
	await assert.rejects(h.coordinator.login({ token: TOKEN, timeoutMs: 30, onHandshakeCode: () => undefined }), { code: "login-timeout" });
	assert.equal(h.stored(), undefined);
});

test("start requires login and revalidates group permissions", async () => {
	const h = harness();
	await assert.rejects(h.coordinator.start(), { code: "not-logged-in" });
	await loginWith(h);
	h.telegram.members.set(BOT.id, { status: "administrator", canManageTopics: false });
	await assert.rejects(h.coordinator.start(), { code: "invalid-group" });
	assert.equal(h.coordinator.status().running, false);
});

test("the running bridge forwards only the owner's group messages and rejects everyone else clearly", async () => {
	const h = harness();
	await loginWith(h);
	h.telegram.push({ chat: GROUP, from: OWNER, text: "queued while stopped" });
	const received: AuthorizedMessage[] = [];
	const first = await h.coordinator.start({ onMessage: async (message) => { received.push(message); } });
	assert.equal(first.alreadyRunning, false);
	assert.equal((await h.coordinator.start()).alreadyRunning, true);
	assert.equal(h.coordinator.status().running, true);

	h.telegram.sent = [];
	h.telegram.push({ chat: GROUP, from: STRANGER, text: "let me in", threadId: 501 });
	h.telegram.push({ chat: GROUP, from: STRANGER, text: "again" });
	h.telegram.push({ chat: { id: OWNER.id, type: "private" }, from: OWNER, text: "from a DM" });
	h.telegram.push({ chat: GROUP, from: OWNER, text: "hello agent", threadId: 501 });
	await until(() => received.length === 1);

	assert.deepEqual(received.map((message) => [message.text, message.threadId]), [["hello agent", 501]]);
	const rejections = h.telegram.sent.filter((message) => /not authorized|only accepts/i.test(message.text));
	assert.deepEqual(rejections.map((message) => [message.chatId, message.threadId]), [[GROUP.id, 501], [OWNER.id, undefined]]);

	assert.equal(await h.coordinator.stop(), true);
	assert.equal(h.coordinator.status().running, false);
	const polls = h.telegram.polls;
	h.telegram.push({ chat: GROUP, from: OWNER, text: "after stop" });
	await new Promise((resolve) => setTimeout(resolve, 20));
	assert.equal(h.telegram.polls, polls, "no polling after stop");
	assert.equal(received.length, 1);
	assert.equal(await h.coordinator.stop(), false);
});

test("logout stops the bridge and removes local credentials", async () => {
	const h = harness();
	await loginWith(h);
	await h.coordinator.start();
	const result = await h.coordinator.logout();
	assert.deepEqual(result, { wasRunning: true, hadCredentials: true });
	assert.equal(h.coordinator.status().running, false);
	assert.equal(h.stored(), undefined);
	await assert.rejects(h.coordinator.start(), { code: "not-logged-in" });
});

test("stop and logout cancel a pending login instead of waiting for it", async () => {
	for (const cancel of ["stop", "logout"] as const) {
		const h = harness();
		let codeShown!: () => void;
		const shown = new Promise<void>((resolve) => { codeShown = resolve; });
		const login = h.coordinator.login({ token: TOKEN, timeoutMs: 60_000, onHandshakeCode: () => codeShown() });
		await shown;
		const started = Date.now();
		await h.coordinator[cancel]();
		await assert.rejects(login, { code: "login-cancelled" }, cancel);
		assert.ok(Date.now() - started < 1000, `${cancel} waited for the login`);
		assert.equal(h.stored(), undefined);
	}
});

test("logout removes unreadable credentials", async () => {
	const h = harness();
	await loginWith(h);
	h.corruptCredentials();
	assert.deepEqual(await h.coordinator.logout(), { wasRunning: false, hadCredentials: true });
	assert.equal(h.stored(), undefined);
});

test("the bridge stops instead of retrying when the token is revoked or another poller holds the bot", async () => {
	for (const [error, code] of [[apiError(401, "Unauthorized"), "invalid-token"], [apiError(409, "Conflict: terminated by other getUpdates request"), "bridge-conflict"]] as const) {
		const h = harness();
		await loginWith(h);
		h.telegram.pollFailures.push(error);
		let stopped: unknown;
		await h.coordinator.start({ onStopped: (reason) => { stopped = reason; } });
		await until(() => stopped !== undefined);
		assert.equal((stopped as { code: string }).code, code);
		assert.equal(h.coordinator.status().running, false);
		assert.equal((await h.coordinator.start()).alreadyRunning, false, "can start again after fixing the cause");
		await h.coordinator.stop();
	}
});

test("the bridge reports recovery after a transient failure", async () => {
	const h = harness();
	await loginWith(h);
	h.telegram.pollFailures.push(new Error("fetch failed"));
	const events: string[] = [];
	await h.coordinator.start({ onError: () => events.push("error"), onRecovered: () => events.push("recovered") });
	await until(() => events.includes("error"));
	h.telegram.push({ chat: GROUP, from: OWNER, text: "back online" });
	await until(() => events.includes("recovered"), 3000); // first retry waits one second
	assert.deepEqual(events, ["error", "recovered"]);
	assert.equal(h.coordinator.status().running, true);
	await h.coordinator.stop();
});

test("anonymous group admins are told to post as themselves", async () => {
	const h = harness();
	const anonymous = h.coordinator.login({
		token: TOKEN,
		onHandshakeCode: (code) => { setTimeout(() => h.telegram.push({ chat: GROUP, from: ANONYMOUS_ADMIN, senderChatId: GROUP.id, text: code }), 5); },
	});
	await assert.rejects(anonymous, { code: "anonymous-owner" });

	await loginWith(h);
	const received: AuthorizedMessage[] = [];
	await h.coordinator.start({ onMessage: async (message) => { received.push(message); } });
	h.telegram.sent = [];
	h.telegram.push({ chat: GROUP, from: ANONYMOUS_ADMIN, senderChatId: GROUP.id, text: "anonymous prompt" });
	await until(() => h.telegram.sent.some((message) => /anonymous/i.test(message.text)));
	assert.equal(received.length, 0);
	await h.coordinator.stop();
});
