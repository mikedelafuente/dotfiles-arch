import assert from "node:assert/strict";
import test from "node:test";
import {
	RemoteControlCoordinator,
	type AuthorizedMessage,
	type RemoteControlAdapters,
	type TelegramBotApi,
	type TelegramChat,
	type TelegramChatMember,
	type TelegramMessage,
	type TelegramUpdate,
	type TelegramUser,
} from "./coordinator.ts";

const TOKEN = "123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi";
const BOT: TelegramUser = { id: 1000, isBot: true, username: "pi_rc_bot" };
const OWNER: TelegramUser = { id: 42, isBot: false, username: "owner" };
const STRANGER: TelegramUser = { id: 99, isBot: false, username: "stranger" };
const GROUP: TelegramChat = { id: -1001, type: "supergroup", title: "Pi", isForum: true };

/** Scriptable Telegram Bot API: updates are delivered through long polling like the real API. */
class FakeTelegram implements TelegramBotApi {
	updates: TelegramUpdate[] = [];
	sent: { chatId: number; threadId?: number; text: string }[] = [];
	topics: string[] = [];
	members = new Map<number, TelegramChatMember>([
		[OWNER.id, { status: "creator" }],
		[BOT.id, { status: "administrator", canManageTopics: true }],
	]);
	chat: TelegramChat = { ...GROUP };
	tokenValid = true;
	polls = 0;
	private nextId = 1;
	private wake?: () => void;

	push(message: Omit<TelegramMessage, "messageId">): void {
		const id = this.nextId++;
		this.updates.push({ updateId: id, message: { messageId: id, ...message } });
		this.wake?.();
	}

	async getMe(): Promise<TelegramUser> {
		if (!this.tokenValid) throw new Error("Unauthorized");
		return BOT;
	}

	async getUpdates(input: { offset?: number; timeoutSeconds: number; signal?: AbortSignal }): Promise<TelegramUpdate[]> {
		this.polls++;
		if (input.offset === -1) return this.updates.slice(-1);
		const pending = () => this.updates.filter((update) => update.updateId >= (input.offset ?? 0));
		if (pending().length || input.timeoutSeconds === 0) return pending();
		await new Promise<void>((resolve, reject) => {
			this.wake = resolve;
			input.signal?.addEventListener("abort", () => reject(input.signal?.reason), { once: true });
		});
		return pending();
	}

	async getChat(): Promise<TelegramChat> { return this.chat; }

	async getChatMember(_chatId: number, userId: number): Promise<TelegramChatMember> {
		return this.members.get(userId) ?? { status: "left" };
	}

	async createForumTopic(_chatId: number, name: string): Promise<{ threadId: number }> {
		this.topics.push(name);
		return { threadId: 500 + this.topics.length };
	}

	async sendMessage(input: { chatId: number; threadId?: number; text: string }): Promise<void> {
		this.sent.push(input);
	}
}

function harness() {
	const telegram = new FakeTelegram();
	let stored: unknown;
	const tokens: string[] = [];
	const adapters = {
		repositories: { getByPath: async () => undefined, list: async () => [], register: async () => undefined, remove: async () => undefined },
		sessions: { list: async () => [], get: async () => undefined, save: async () => undefined },
		workspaces: {
			create: async (_repository, branch) => ({ path: `/tmp/${branch}`, branch, created: true }),
			adopt: async (path, branch = "main") => ({ path, branch, created: false }),
		},
		pi: { create: async () => ({ id: "pi" }) },
		telegram: { createSessionTopic: async () => ({ id: "topic" }) },
		credentials: {
			read: async () => stored,
			write: async (value: unknown) => { stored = structuredClone(value); },
			clear: async () => { stored = undefined; },
		},
		telegramBot: (token: string) => { tokens.push(token); return telegram; },
	} satisfies RemoteControlAdapters;
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date("2026-01-01T00:00:00Z"));
	return { telegram, coordinator, tokens, stored: () => stored };
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

async function until(condition: () => boolean): Promise<void> {
	for (let i = 0; i < 200 && !condition(); i++) await new Promise((resolve) => setTimeout(resolve, 5));
	assert.ok(condition(), "condition not reached");
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
