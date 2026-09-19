/** Shared fakes for remote-control tests. Not a test file itself: `node --test *.test.ts` skips it. */
import assert from "node:assert/strict";
import {
	RemoteControlCoordinator,
	RemoteControlError,
	type AgentProcess,
	type AgentSession,
	type AgentSessionStore,
	type AuthorizedMessage,
	type LivePiSession,
	type PiActivity,
	type PiSessionAdapter,
	type PiSessionEvents,
	type RemoteControlAdapters,
	type Repository,
	type RepositoryRegistry,
	type Workspace,
	type WorkspaceAdapter,
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
	deleted: number[] = [];
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

	async deleteForumTopic(input: { chatId: number; threadId: number }): Promise<void> {
		this.deleted.push(input.threadId);
		this.deletedTopics.add(input.threadId);
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

/** A Pi conversation, recording what the bridge delivers to it. */
export class FakePiSession implements LivePiSession {
	id = "pi-current";
	name = "fix-flake";
	workspace = "/work/demo";
	branch = "main";
	repositoryPath = "/work/demo";
	sessionFile?: string = "/sessions/pi-current.jsonl";
	idle = true;
	delivered: [kind: "prompt" | "steer" | "followUp", text: string][] = [];
	renamedTo: string[] = [];
	isIdle(): boolean { return this.idle; }
	prompt(text: string): void { this.delivered.push(["prompt", text]); }
	steer(text: string): void { this.delivered.push(["steer", text]); }
	followUp(text: string): void { this.delivered.push(["followUp", text]); }
	rename(name: string): void { this.renamedTo.push(name); this.name = name; }
}

/** A Pi conversation running in its own process, started by remote control. */
export class FakeAgentProcess extends FakePiSession implements AgentProcess {
	closed = false;
	readonly events: PiSessionEvents;
	constructor(events: PiSessionEvents) { super(); this.events = events; }
	async close(): Promise<void> { this.closed = true; }
	/** Reports Pi activity the way the real process adapter does. */
	report(activity: PiActivity): void { this.events.activity(activity); }
}

/** Git worktrees as a set of paths, each with its checked-out branch. */
export class FakeWorkspaces implements WorkspaceAdapter {
	/** Existing workspaces and their branches. */
	branches = new Map<string, string>([["/work/demo", "main"]]);
	created: Workspace[] = [];
	removed: string[] = [];
	mainLineBranch = "main";
	async create(repository: Repository, branch: string): Promise<Workspace> {
		const path = `${repository.path}.worktrees/${branch.replace(/\//g, "-")}`;
		if (this.branches.has(path)) throw new Error(`already exists: ${path}`);
		this.branches.set(path, branch);
		const workspace = { path, branch, created: true };
		this.created.push(workspace);
		return workspace;
	}
	async remove(workspace: Workspace): Promise<void> {
		this.branches.delete(workspace.path);
		this.removed.push(workspace.path);
	}
	async mainLine(): Promise<string> { return this.mainLineBranch; }
	async inspect(path: string): Promise<{ branch: string } | undefined> {
		const branch = this.branches.get(path);
		return branch === undefined ? undefined : { branch };
	}
}

/** Starts and resumes fake Pi processes; histories are the session files that "exist". */
export class FakePiSessions implements PiSessionAdapter {
	processes: FakeAgentProcess[] = [];
	histories = new Set<string>(["/sessions/pi-current.jsonl"]);
	/** Makes the next create or resume fail. */
	failNext?: Error;
	private next = 1;
	async create(input: { name: string; repository: Repository; workspace: Workspace }, events: PiSessionEvents): Promise<AgentProcess> {
		this.throwIfFailing();
		const process = new FakeAgentProcess(events);
		process.id = `pi-new-${this.next++}`;
		Object.assign(process, { name: input.name, workspace: input.workspace.path, branch: input.workspace.branch, repositoryPath: input.repository.path });
		process.sessionFile = `/sessions/${process.id}.jsonl`;
		this.histories.add(process.sessionFile);
		this.processes.push(process);
		return process;
	}
	async resume(session: AgentSession, events: PiSessionEvents): Promise<AgentProcess> {
		this.throwIfFailing();
		const process = new FakeAgentProcess(events);
		Object.assign(process, {
			id: session.piSessionId, name: session.name, workspace: session.workspace, branch: session.branch,
			repositoryPath: session.repositoryPath, sessionFile: session.piSessionFile,
		});
		this.processes.push(process);
		return process;
	}
	async hasHistory(session: AgentSession): Promise<boolean> {
		return session.piSessionFile !== undefined && this.histories.has(session.piSessionFile);
	}
	/** The most recently started process. */
	get last(): FakeAgentProcess { return this.processes.at(-1)!; }
	private throwIfFailing(): void {
		const failure = this.failNext;
		this.failNext = undefined;
		if (failure) throw failure;
	}
}

/** A logged-in coordinator over fakes, ready to start. */
export async function harness() {
	const telegram = new FakeTelegram();
	const stores = memoryStores();
	const workspaces = new FakeWorkspaces();
	const pi = new FakePiSessions();
	let stored: unknown;
	const adapters = {
		...stores,
		workspaces,
		pi,
		credentials: { read: async () => stored, write: async (value: unknown) => { stored = structuredClone(value); }, clear: async () => { stored = undefined; } },
		telegramBot: () => telegram,
	} satisfies RemoteControlAdapters;
	let now = new Date("2026-01-01T00:00:00Z").getTime();
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date(now), { progressIntervalMs: 10 });
	await coordinator.login({
		token: TOKEN,
		onHandshakeCode: (code) => { setTimeout(() => telegram.push({ chat: GROUP, from: OWNER, text: code }), 5); },
	});
	assert.equal(telegram.topics.length, 1, "control topic");
	telegram.sent = [];
	return { telegram, stores, workspaces, pi, coordinator, advance: (ms: number) => { now += ms; } };
}

export type Harness = Awaited<ReturnType<typeof harness>>;

/** The control topic `harness()` creates at login. */
export const CONTROL_TOPIC = 501;

/** Starts remote control with `pi` as the current conversation. */
export async function startWith(h: Harness, pi = new FakePiSession(), onMessage?: (message: AuthorizedMessage) => Promise<void>) {
	const result = await h.coordinator.start({ session: pi, onMessage });
	assert.ok(result.session, "current Pi session exposed");
	return { pi, session: result.session, topic: Number(result.session.topicId) };
}
