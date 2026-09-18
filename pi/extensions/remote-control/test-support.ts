/** Shared fakes for remote-control tests. Not a test file itself: `node --test *.test.ts` skips it. */
import assert from "node:assert/strict";
import {
	RemoteControlError,
	type AgentSession,
	type AgentSessionStore,
	type Repository,
	type RepositoryRegistry,
	type TelegramBotApi,
	type TelegramChat,
	type TelegramChatMember,
	type TelegramMessage,
	type TelegramUpdate,
	type TelegramUser,
} from "./coordinator.ts";

export const TOKEN = "123456:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi";
export const BOT: TelegramUser = { id: 1000, isBot: true, username: "pi_rc_bot" };
export const OWNER: TelegramUser = { id: 42, isBot: false, username: "owner" };
export const STRANGER: TelegramUser = { id: 99, isBot: false, username: "stranger" };
export const GROUP: TelegramChat = { id: -1001, type: "supergroup", title: "Pi", isForum: true };

export type SentMessage = { chatId: number; threadId?: number; text: string; messageId: number };

/** Scriptable Telegram Bot API: updates are delivered through long polling like the real API. */
export class FakeTelegram implements TelegramBotApi {
	updates: TelegramUpdate[] = [];
	sent: SentMessage[] = [];
	edits: { chatId: number; messageId: number; text: string }[] = [];
	topics: string[] = [];
	renamed: { threadId: number; name: string }[] = [];
	/** Topics deleted in Telegram: posting into them fails like the real API. */
	deletedTopics = new Set<number>();
	members = new Map<number, TelegramChatMember>([
		[OWNER.id, { status: "creator" }],
		[BOT.id, { status: "administrator", canManageTopics: true }],
	]);
	chat: TelegramChat = { ...GROUP };
	tokenValid = true;
	polls = 0;
	/** Errors thrown by the next getUpdates calls, in order. */
	pollFailures: Error[] = [];
	private nextId = 1;
	private nextMessageId = 10_000;
	private wake?: () => void;

	push(message: Omit<TelegramMessage, "messageId">): void {
		const id = this.nextId++;
		this.updates.push({ updateId: id, message: { messageId: id, ...message } });
		this.wake?.();
	}

	/** Messages the bot posted into one topic. */
	inTopic(threadId: number): SentMessage[] {
		return this.sent.filter((message) => message.threadId === threadId);
	}

	async getMe(): Promise<TelegramUser> {
		if (!this.tokenValid) throw new Error("Unauthorized");
		return BOT;
	}

	async getUpdates(input: { offset?: number; timeoutSeconds: number; signal?: AbortSignal }): Promise<TelegramUpdate[]> {
		this.polls++;
		if (input.offset === -1) return this.updates.slice(-1);
		const failure = this.pollFailures.shift();
		if (failure) throw failure;
		const pending = () => this.updates.filter((update) => update.updateId >= (input.offset ?? 0));
		if (pending().length || input.timeoutSeconds === 0) return pending();
		input.signal?.throwIfAborted();
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

	async editForumTopic(input: { chatId: number; threadId: number; name: string }): Promise<void> {
		if (this.deletedTopics.has(input.threadId)) throw apiError(400, "Bad Request: message thread not found");
		this.renamed.push({ threadId: input.threadId, name: input.name });
	}

	async sendMessage(input: { chatId: number; threadId?: number; text: string }): Promise<{ messageId: number }> {
		if (input.threadId !== undefined && this.deletedTopics.has(input.threadId)) throw apiError(400, "Bad Request: message thread not found");
		const messageId = this.nextMessageId++;
		this.sent.push({ ...input, messageId });
		return { messageId };
	}

	async editMessageText(input: { chatId: number; messageId: number; text: string }): Promise<void> {
		this.edits.push(input);
	}
}

export function apiError(errorCode: number, message: string): Error {
	return Object.assign(new Error(message), { errorCode });
}

/** In-memory repository registry and agent-session store with the same invariants as the JSON adapters. */
export function memoryStores(): { repositories: RepositoryRegistry & { items: Repository[] }; sessions: AgentSessionStore & { items: AgentSession[] } } {
	const repositories: Repository[] = [];
	const sessions: AgentSession[] = [];
	const assertWorkspaceFree = (session: AgentSession) => {
		if (sessions.some((item) => item.id !== session.id && item.workspace === session.workspace)) {
			throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${session.workspace}`);
		}
	};
	return {
		repositories: {
			items: repositories,
			getByPath: async (path) => repositories.find((item) => item.path === path),
			list: async () => [...repositories],
			register: async (repository) => { repositories.push(structuredClone(repository)); },
			remove: async (path) => { repositories.splice(repositories.findIndex((item) => item.path === path), 1); },
		},
		sessions: {
			items: sessions,
			list: async () => structuredClone(sessions),
			get: async (id) => structuredClone(sessions.find((item) => item.id === id)),
			save: async (session) => {
				assertWorkspaceFree(session);
				sessions.push(structuredClone(session));
			},
			update: async (session) => {
				const index = sessions.findIndex((item) => item.id === session.id);
				if (index === -1) throw new RemoteControlError("session-not-found", `Agent session not found: ${session.id}`);
				assertWorkspaceFree(session);
				sessions[index] = structuredClone(session);
			},
		},
	};
}

export async function until(condition: () => boolean, timeoutMs = 1000): Promise<void> {
	for (let i = 0; i < timeoutMs / 5 && !condition(); i++) await new Promise((resolve) => setTimeout(resolve, 5));
	assert.ok(condition(), "condition not reached");
}

export const tick = (ms = 20) => new Promise((resolve) => setTimeout(resolve, ms));
