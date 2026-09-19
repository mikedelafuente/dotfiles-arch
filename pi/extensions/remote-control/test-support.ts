/** Shared fakes for remote-control tests. Not a test file itself: `node --test *.test.ts` skips it. */
import assert from "node:assert/strict";
import {
	RemoteControlCoordinator,
	RemoteControlError,
	type AgentProcess,
	type AgentSession,
	type AgentSessionStore,
	type AuthorizedMessage,
	type CoordinatorOptions,
	type InlineButton,
	type LeaseHolder,
	type LivePiSession,
	type NextConversation,
	type PiActivity,
	type PiCommand,
	type PiSessionAdapter,
	type PiSessionEvents,
	type PiSessionInfo,
	type RemoteControlAdapters,
	type Repository,
	type RepositoryRegistry,
	type SessionLeases,
	type Workspace,
	type WorkspaceAdapter,
	type TelegramBotApi,
	type TelegramCallbackQuery,
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

export type SentMessage = { chatId: number; threadId?: number; text: string; messageId: number; buttons?: InlineButton[][] };

/** Scriptable Telegram Bot API: updates are delivered through long polling like the real API. */
export class FakeTelegram implements TelegramBotApi {
	updates: TelegramUpdate[] = [];
	sent: SentMessage[] = [];
	edits: { chatId: number; messageId: number; text: string; buttons?: InlineButton[][] }[] = [];
	/** Callback query answers, in order. */
	answers: { id: string; text?: string }[] = [];
	/** Command menus set with setMyCommands. */
	menus: { chatId: number; commands: { command: string; description: string }[] }[] = [];
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

	/** A press of an inline button on `message`, from `from`; `threadId` overrides the message's topic. */
	press(message: SentMessage, label: string, from: TelegramUser = OWNER, threadId = message.threadId): string {
		const button = message.buttons?.flat().find((candidate) => candidate.text === label);
		assert.ok(button, `button "${label}" on: ${message.text}`);
		const id = this.nextId++;
		const callbackQuery: TelegramCallbackQuery = { id: `cb-${id}`, from, data: button.data, message: { messageId: message.messageId, chatId: message.chatId, threadId } };
		this.updates.push({ updateId: id, callbackQuery });
		this.wake?.();
		return callbackQuery.id;
	}

	/** The answer to one callback query, once the bridge has given it. */
	answerTo(callbackId: string): { id: string; text?: string } | undefined {
		return this.answers.find((answer) => answer.id === callbackId);
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

	async sendMessage(input: { chatId: number; threadId?: number; text: string; buttons?: InlineButton[][] }): Promise<{ messageId: number }> {
		if (input.threadId !== undefined && this.deletedTopics.has(input.threadId)) throw apiError(400, "Bad Request: message thread not found");
		const messageId = this.nextMessageId++;
		this.sent.push({ ...input, messageId });
		return { messageId };
	}

	async editMessageText(input: { chatId: number; messageId: number; text: string; buttons?: InlineButton[][] }): Promise<void> {
		this.edits.push(input);
	}

	async answerCallbackQuery(input: { id: string; text?: string }): Promise<void> {
		this.answers.push(input);
	}

	async setMyCommands(input: { chatId: number; commands: { command: string; description: string }[] }): Promise<void> {
		this.menus.push(input);
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
	/** What Pi discovered: read on every request, like Pi's own list after a reload. */
	commandList: PiCommand[] = [];
	aborts = 0;
	/** Built-ins run through this session, as [name, argument]. */
	builtins: [name: string, args: string][] = [];
	isIdle(): boolean { return this.idle; }
	async commands(): Promise<PiCommand[]> { return structuredClone(this.commandList); }
	async abort(): Promise<void> { this.aborts++; }
	async compact(instructions?: string): Promise<{ tokensBefore?: number; estimatedTokensAfter?: number }> {
		this.builtins.push(["compact", instructions ?? ""]);
		return { tokensBefore: 1000, estimatedTokensAfter: 200 };
	}
	async setThinkingLevel(level: string): Promise<void> {
		this.builtins.push(["thinking", level]);
	}
	model = "anthropic/claude-sonnet-5";
	availableModels = ["anthropic/claude-sonnet-5", "anthropic/claude-opus-5"];
	/** Extension commands run through this session, after the owner approved them. */
	extensionCommands: string[] = [];
	async info(): Promise<PiSessionInfo> {
		return {
			id: this.id, file: this.sessionFile, name: this.name || undefined, model: this.model, thinkingLevel: "medium",
			messages: { user: 3, assistant: 4, toolCalls: 5 },
			tokens: { input: 1200, output: 340, cacheRead: 5000, cacheWrite: 0 },
			cost: 0.0421,
			context: { tokens: 18000, window: 200000, percent: 9 },
		};
	}
	async models(): Promise<{ current?: string; available: string[] }> {
		return { current: this.model, available: [...this.availableModels] };
	}
	async setModel(provider: string, modelId: string): Promise<void> {
		const model = `${provider}/${modelId}`;
		if (!this.availableModels.includes(model)) throw new Error(`Model not found: ${model}`);
		this.builtins.push(["model", model]);
		this.model = model;
	}
	async runExtensionCommand(text: string): Promise<void> { this.extensionCommands.push(text); }
	prompt(text: string): void { this.delivered.push(["prompt", text]); }
	steer(text: string): void { this.delivered.push(["steer", text]); }
	followUp(text: string): void { this.delivered.push(["followUp", text]); }
	async rename(name: string): Promise<void> { this.renamedTo.push(name); this.name = name; }
	/** The local `/new` and `/reload` this conversation was asked to run, in order. */
	runtimeReplacements: string[] = [];
	/** Called as Pi would start replacing its runtime. */
	onReplaceRuntime?: () => void;
	async replaceRuntime(command: "new" | "reload"): Promise<void> {
		this.onReplaceRuntime?.();
		this.runtimeReplacements.push(command);
	}
}

/** A Pi conversation running in its own process, started by remote control. */
export class FakeAgentProcess extends FakePiSession implements AgentProcess {
	closed = false;
	/** Makes close() fail, leaving the process running. */
	closeFailure?: Error;
	readonly events: PiSessionEvents;
	private readonly histories: Set<string>;
	constructor(events: PiSessionEvents, histories: Set<string>) { super(); this.events = events; this.histories = histories; }
	async close(): Promise<void> {
		if (this.closeFailure) throw this.closeFailure;
		this.closed = true;
	}
	reloads = 0;
	/** Pi's `/new`: the next conversation has no history until its first response. */
	async newConversation(): Promise<NextConversation | undefined> {
		this.id = `${this.id}-next`;
		this.sessionFile = `/sessions/${this.id}.jsonl`;
		this.name = "";
		return { id: this.id, sessionFile: this.sessionFile };
	}
	async reload(): Promise<void> { this.reloads++; }
	/** Reports Pi activity the way the real process adapter does. Like Pi, the first response writes the history file. */
	report(activity: PiActivity): void {
		if (activity.type === "response" && this.sessionFile) this.histories.add(this.sessionFile);
		this.events.activity(activity);
	}
}

/** Git worktrees as a set of paths, each with its checked-out branch. */
export class FakeWorkspaces implements WorkspaceAdapter {
	/** Existing workspaces and their branches. */
	branches = new Map<string, string>([["/work/demo", "main"]]);
	created: Workspace[] = [];
	removed: string[] = [];
	mainLineBranch = "main";
	/** Makes remove() fail, leaving the worktree and branch behind. */
	removeFailure?: Error;
	async create(repository: Repository, branch: string): Promise<Workspace> {
		const path = `${repository.path}.worktrees/${branch.replace(/\//g, "-")}`;
		if (this.branches.has(path)) throw new Error(`already exists: ${path}`);
		this.branches.set(path, branch);
		const workspace = { path, branch, created: true };
		this.created.push(workspace);
		return workspace;
	}
	async remove(workspace: Workspace): Promise<void> {
		if (this.removeFailure) throw this.removeFailure;
		this.branches.delete(workspace.path);
		this.removed.push(workspace.path);
	}
	async mainLine(): Promise<string> { return this.mainLineBranch; }
	async inspect(path: string): Promise<{ branch: string } | undefined> {
		const branch = this.branches.get(path);
		return branch === undefined ? undefined : { branch };
	}
}

/**
 * Starts and resumes fake Pi processes; histories are the session files that
 * "exist". As in Pi, a new conversation has no file until its first response.
 */
export class FakePiSessions implements PiSessionAdapter {
	processes: FakeAgentProcess[] = [];
	histories = new Set<string>(["/sessions/pi-current.jsonl"]);
	/** Makes the next create or resume fail. */
	failNext?: Error;
	private next = 1;
	async create(input: { name: string; repository: Repository; workspace: Workspace }, events: PiSessionEvents): Promise<AgentProcess> {
		this.throwIfFailing();
		const process = new FakeAgentProcess(events, this.histories);
		process.id = `pi-new-${this.next++}`;
		Object.assign(process, { name: input.name, workspace: input.workspace.path, branch: input.workspace.branch, repositoryPath: input.repository.path });
		process.sessionFile = `/sessions/${process.id}.jsonl`;
		this.processes.push(process);
		return process;
	}
	async resume(session: AgentSession, events: PiSessionEvents): Promise<AgentProcess> {
		this.throwIfFailing();
		if (!(await this.hasHistory(session)) && !session.unprompted) throw new Error(`The Pi history of ${session.name} was not found.`);
		const process = new FakeAgentProcess(events, this.histories);
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

/** Live Pi processes holding each conversation, by PID; stale leases are the file adapter's concern. */
export class FakeLeases implements SessionLeases {
	held = new Map<string, number[]>();
	async holders(piSessionId: string): Promise<LeaseHolder[]> {
		return (this.held.get(piSessionId) ?? []).map((pid) => ({ pid, here: pid === process.pid }));
	}
}

/** A logged-in coordinator over fakes, ready to start. */
export async function harness(options: CoordinatorOptions = {}) {
	const telegram = new FakeTelegram();
	const stores = memoryStores();
	const workspaces = new FakeWorkspaces();
	const pi = new FakePiSessions();
	const leases = new FakeLeases();
	let stored: unknown;
	const adapters = {
		...stores,
		workspaces,
		pi,
		leases,
		credentials: { read: async () => stored, write: async (value: unknown) => { stored = structuredClone(value); }, clear: async () => { stored = undefined; } },
		telegramBot: () => telegram,
	} satisfies RemoteControlAdapters;
	let now = new Date("2026-01-01T00:00:00Z").getTime();
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date(now), { progressIntervalMs: 10, ...options });
	await coordinator.login({
		token: TOKEN,
		onHandshakeCode: (code) => { setTimeout(() => telegram.push({ chat: GROUP, from: OWNER, text: code }), 5); },
	});
	assert.equal(telegram.topics.length, 1, "control topic");
	telegram.sent = [];
	return { telegram, stores, workspaces, pi, leases, coordinator, advance: (ms: number) => { now += ms; } };
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
