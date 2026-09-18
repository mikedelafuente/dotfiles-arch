/**
 * Remote-control domain seam.
 *
 * This module deliberately knows nothing about Telegram, Pi RPC, or Git. Those
 * concerns are adapters so coordinator behavior can be tested with fakes.
 */

import { randomBytes, randomUUID } from "node:crypto";
import {
	condenseForTelegram,
	describeTool,
	failureText,
	parseSessionTopicInput,
	renderProgress,
	SESSION_TOPIC_HELP,
	topicTitle,
	type ToolProgress,
} from "./messages.ts";

export type Repository = {
	id: string;
	path: string;
	name: string;
	registeredAt: string;
};

export type AgentSession = {
	id: string;
	name: string;
	repositoryId: string;
	repositoryPath: string;
	workspace: string;
	branch: string;
	piSessionId: string;
	topicId: string;
	topicName: string;
	createdAt: string;
	status: "active" | "disconnected" | "stale" | "missing-workspace";
};

export type CreateSessionInput = {
	name: string;
	repositoryPath: string;
	branch?: string;
	workspace?: string;
};

export type Workspace = {
	path: string;
	branch: string;
	created: boolean;
};

export interface RepositoryRegistry {
	getByPath(path: string): Promise<Repository | undefined>;
	list(): Promise<Repository[]>;
	register(repository: Repository): Promise<void>;
	remove(path: string): Promise<void>;
}

export interface AgentSessionStore {
	list(): Promise<AgentSession[]>;
	save(session: AgentSession): Promise<void>;
	get(id: string): Promise<AgentSession | undefined>;
	/** Replaces a stored session with the same id. */
	update(session: AgentSession): Promise<void>;
}

export interface WorkspaceAdapter {
	create(repository: Repository, branch: string): Promise<Workspace>;
	adopt(path: string, branch?: string): Promise<Workspace>;
	remove?(workspace: Workspace): Promise<void>;
}

export interface PiSessionAdapter {
	create(input: { name: string; repository: Repository; workspace: Workspace }): Promise<{ id: string }>;
	remove?(id: string): Promise<void>;
}

export interface TelegramTransport {
	createSessionTopic(name: string): Promise<{ id: string }>;
	removeTopic?(id: string): Promise<void>;
}

export interface CredentialStore {
	read(): Promise<unknown | undefined>;
	write(credentials: unknown): Promise<void>;
	clear(): Promise<void>;
}

export type TelegramUser = { id: number; isBot: boolean; username?: string };

export type TelegramChat = {
	id: number;
	type: "private" | "group" | "supergroup" | "channel";
	title?: string;
	/** Present only for public chats. */
	username?: string;
	isForum?: boolean;
};

export type TelegramMessage = {
	messageId: number;
	chat: TelegramChat;
	from?: TelegramUser;
	/** Set when a chat posts as itself; equals `chat.id` for anonymous group admins. */
	senderChatId?: number;
	threadId?: number;
	text?: string;
};

export type TelegramUpdate = { updateId: number; message?: TelegramMessage };

export type TelegramChatMember = {
	status: "creator" | "administrator" | "member" | "restricted" | "left" | "kicked";
	canManageTopics?: boolean;
};

/**
 * The subset of the Telegram Bot API remote control uses, bound to one bot token.
 * Bot API failures reject with an error carrying the API's numeric `errorCode`.
 */
export interface TelegramBotApi {
	getMe(): Promise<TelegramUser>;
	/** Long-polls for updates. `offset: -1` returns only the newest pending update. */
	getUpdates(input: { offset?: number; timeoutSeconds: number; signal?: AbortSignal }): Promise<TelegramUpdate[]>;
	getChat(chatId: number): Promise<TelegramChat>;
	getChatMember(chatId: number, userId: number): Promise<TelegramChatMember>;
	createForumTopic(chatId: number, name: string): Promise<{ threadId: number }>;
	editForumTopic(input: { chatId: number; threadId: number; name: string }): Promise<void>;
	sendMessage(input: { chatId: number; threadId?: number; text: string }): Promise<{ messageId: number }>;
	editMessageText(input: { chatId: number; messageId: number; text: string }): Promise<void>;
}

/** Machine-local remote-control credentials: never synchronized or committed. */
export type RemoteControlCredentials = {
	version: 1;
	botToken: string;
	bot: { id: number; username?: string };
	owner: { id: number; username?: string };
	group: { id: number; title?: string; controlTopicId: number };
	authenticatedAt: string;
};

/** An owner message from the approved forum group, delivered by the running bridge. */
export type AuthorizedMessage = { messageId: number; threadId?: number; text: string };

export type LoginOptions = {
	token: string;
	/** Shows the one-time code the owner must send in the forum group. */
	onHandshakeCode(code: string, bot: TelegramUser): void | Promise<void>;
	timeoutMs?: number;
	signal?: AbortSignal;
};

/**
 * The Pi conversation running in this process. Remote control exposes it as an
 * agent session and delivers its session topic's messages to it.
 */
export interface LivePiSession {
	readonly id: string;
	/** Display name; empty when the conversation is unnamed. */
	readonly name: string;
	/** Root of the Git worktree the conversation works in. */
	readonly workspace: string;
	readonly branch: string;
	/** The repository to approve: the main checkout when `workspace` is a linked worktree. */
	readonly repositoryPath: string;
	isIdle(): boolean;
	/** Starts a run with a new user message. */
	prompt(text: string): void;
	/** Redirects the current run. */
	steer(text: string): void;
	/** Queues a user message for after the current run. */
	followUp(text: string): void;
}

/** What a live Pi session is doing, reported to its session topic. Tool output is deliberately absent. */
export type PiActivity =
	| { type: "run-start"; prompt?: string }
	| { type: "tool-start"; toolCallId: string; toolName: string; args: unknown }
	| { type: "tool-end"; toolCallId: string; isError: boolean }
	| { type: "response"; text: string; error?: string; aborted?: boolean }
	/** Pi will not continue on its own: no retry, compaction, or queued follow-up is left. */
	| { type: "settled" };

export type StartOptions = {
	/** The current Pi conversation to expose; omitted outside a Git repository. */
	session?: LivePiSession;
	/** Owner messages that are not for a running agent session, such as control-topic messages. */
	onMessage?(message: AuthorizedMessage): Promise<void>;
	/** A recoverable failure; polling retries with backoff. */
	onError?(error: unknown): void;
	/** Polling works again after one or more onError calls. */
	onRecovered?(): void;
	/** The bridge stopped itself because retrying cannot succeed. */
	onStopped?(reason: RemoteControlError): void;
	/** Sending to or editing a session topic failed; the bridge keeps running. */
	onDeliveryError?(error: unknown): void;
};

export type CoordinatorOptions = {
	/** Minimum time between edits of a progress message; Telegram rate-limits edits. */
	progressIntervalMs?: number;
};

export type RemoteControlStatus = {
	running: boolean;
	bot?: string;
	group?: string;
	/** Session topics the running bridge routes to Pi. */
	topics: string[];
};

export type RemoteControlAdapters = {
	repositories: RepositoryRegistry;
	sessions: AgentSessionStore;
	workspaces: WorkspaceAdapter;
	pi: PiSessionAdapter;
	telegram: TelegramTransport;
	credentials: CredentialStore;
	telegramBot(token: string): TelegramBotApi;
};

export class RemoteControlError extends Error {
	readonly code:
		| "repository-not-approved"
		| "duplicate-workspace"
		| "session-not-found"
		| "invalid-session-name"
		| "invalid-token"
		| "invalid-group"
		| "login-timeout"
		| "login-cancelled"
		| "anonymous-owner"
		| "bridge-conflict"
		| "not-logged-in";

	constructor(code: RemoteControlError["code"], message: string) {
		super(message);
		this.name = "RemoteControlError";
		this.code = code;
	}
}

function id(prefix: string): string {
	return `${prefix}-${randomUUID()}`;
}

const LOGIN_TIMEOUT_MS = 5 * 60_000;
const POLL_TIMEOUT_SECONDS = 25;
const MAX_RETRY_DELAY_MS = 30_000;
const CONTROL_TOPIC_NAME = "Pi remote control";
const TOKEN_PATTERN = /^\d+:[\w-]{30,}$/;
const DEFAULT_PROGRESS_INTERVAL_MS = 5000;
const MAX_RATE_LIMIT_WAIT_SECONDS = 60;
const DEFAULT_SESSION_NAME = "agent";

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

const ANONYMOUS_OWNER_MESSAGE = "Anonymous admin messages cannot be verified; turn off Remain anonymous for your account in this group.";

/** Bot API failures that retrying cannot fix: the bridge must stop instead. */
function fatalPollError(error: unknown): RemoteControlError | undefined {
	const code = (error as { errorCode?: number } | undefined)?.errorCode;
	if (code === 401 || code === 404) return new RemoteControlError("invalid-token", "Telegram rejected the bot token; run /rc login again.");
	if (code === 409) {
		return new RemoteControlError("bridge-conflict", "Another process is polling this bot (another Pi running /rc, or a webhook is set).");
	}
	return undefined;
}

/** Telegram's answer for a topic that was deleted, as opposed to a transient failure. */
function isMissingTopic(error: unknown): boolean {
	return (error as { errorCode?: number } | undefined)?.errorCode === 400
		&& /thread not found|TOPIC_DELETED|TOPIC_ID_INVALID/i.test(errorMessage(error));
}

/** Runs a Telegram call, waiting out rate limits (429 retry_after) a couple of times before giving up. */
async function withRateLimitRetry(call: () => Promise<void>, signal: AbortSignal): Promise<void> {
	for (let attempt = 0; ; attempt++) {
		try {
			return await call();
		} catch (error) {
			const { errorCode, retryAfter } = (error ?? {}) as { errorCode?: number; retryAfter?: number };
			if (errorCode !== 429 || retryAfter === undefined || retryAfter > MAX_RATE_LIMIT_WAIT_SECONDS || attempt >= 2) throw error;
			await sleep(retryAfter * 1000, signal);
		}
	}
}

function isCredentials(value: unknown): value is RemoteControlCredentials {
	const candidate = value as RemoteControlCredentials | undefined;
	return candidate?.version === 1 && typeof candidate.botToken === "string"
		&& typeof candidate.owner?.id === "number" && typeof candidate.group?.id === "number"
		&& typeof candidate.group.controlTopicId === "number";
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
	return new Promise((resolve) => {
		const timer = setTimeout(resolve, ms);
		signal.addEventListener("abort", () => { clearTimeout(timer); resolve(); }, { once: true });
	});
}

async function verifyToken(api: TelegramBotApi): Promise<TelegramUser> {
	let bot: TelegramUser;
	try {
		bot = await api.getMe();
	} catch (error) {
		throw new RemoteControlError("invalid-token", `Telegram rejected the bot token: ${errorMessage(error)}`);
	}
	if (!bot.isBot) throw new RemoteControlError("invalid-token", "The token does not belong to a Telegram bot.");
	return bot;
}

/** Rejects anything other than a private forum group the owner administers and the bot can post topics in. */
async function verifyGroup(api: TelegramBotApi, chat: TelegramChat, botId: number, ownerId: number): Promise<void> {
	const reject = (reason: string) => { throw new RemoteControlError("invalid-group", `Invalid remote-control group: ${reason}`); };
	if (chat.type !== "supergroup" || !chat.isForum) reject("use a group with Topics enabled, not a direct message or plain group.");
	if (chat.username) reject(`@${chat.username} is public; use a private group.`);
	const owner = await api.getChatMember(chat.id, ownerId);
	if (owner.status !== "creator" && owner.status !== "administrator") reject("you must be an administrator of the group.");
	const bot = await api.getChatMember(chat.id, botId);
	if (bot.status !== "administrator") reject("make the bot a group administrator.");
	if (!bot.canManageTopics) reject("grant the bot the Manage Topics administrator right.");
}

/** Acknowledges pending updates so messages sent while remote control was inactive are never acted on. */
async function drainUpdates(api: TelegramBotApi): Promise<number | undefined> {
	const [latest] = await api.getUpdates({ offset: -1, timeoutSeconds: 0 });
	return latest ? latest.updateId + 1 : undefined;
}

type Progress = {
	startedAt: number;
	prompt?: string;
	tools: ToolProgress[];
	/**
	 * The latest run's failure, held until Pi settles: extensions see `agent_end`
	 * before Pi decides to auto-retry, so a retried error must not be reported.
	 */
	failure?: string;
	messageId?: number;
	shown?: string;
	timer?: ReturnType<typeof setTimeout>;
};

/** A session topic the running bridge delivers to one live Pi session. */
type Route = {
	session: AgentSession;
	/** The session topic's Telegram thread id (`session.topicId` as a number). */
	threadId: number;
	pi: LivePiSession;
	/** Serializes this topic's Telegram calls so edits never overtake the message they edit. */
	outbox: Promise<void>;
	progress?: Progress;
};

type Bridge = {
	abort: AbortController;
	done: Promise<void>;
	credentials: RemoteControlCredentials;
	api: TelegramBotApi;
	options: StartOptions;
	/** Keyed by Telegram thread id. */
	routes: Map<number, Route>;
};

/** The single authority for repository and agent-session invariants. */
export class RemoteControlCoordinator {
	private creationTail: Promise<void> = Promise.resolve();
	private bridge?: Bridge;
	private lifecycleTail: Promise<void> = Promise.resolve();
	private pendingLogin?: AbortController;

	private readonly adapters: RemoteControlAdapters;
	private readonly now: () => Date;
	private readonly progressIntervalMs: number;

	constructor(adapters: RemoteControlAdapters, now = () => new Date(), options: CoordinatorOptions = {}) {
		this.adapters = adapters;
		this.now = now;
		this.progressIntervalMs = options.progressIntervalMs ?? DEFAULT_PROGRESS_INTERVAL_MS;
	}

	private withCreationLock<T>(operation: () => Promise<T>): Promise<T> {
		const previous = this.creationTail;
		let release!: () => void;
		this.creationTail = new Promise<void>((resolve) => { release = resolve; });
		return previous.then(operation).finally(release);
	}

	registerRepository(path: string, name?: string): Promise<Repository> {
		return this.withCreationLock(() => this.registerRepositoryLocked(path, name));
	}

	private async registerRepositoryLocked(path: string, name = path.split("/").filter(Boolean).pop() || path): Promise<Repository> {
		const existing = await this.adapters.repositories.getByPath(path);
		if (existing) return existing;
		const repository: Repository = { id: id("repo"), path, name, registeredAt: this.now().toISOString() };
		await this.adapters.repositories.register(repository);
		return repository;
	}

	listRepositories(): Promise<Repository[]> {
		return this.adapters.repositories.list();
	}

	createSession(input: CreateSessionInput): Promise<AgentSession> {
		return this.withCreationLock(() => this.createSessionLocked(input));
	}

	private async createSessionLocked(input: CreateSessionInput): Promise<AgentSession> {
		const name = input.name.trim();
		if (!name) throw new RemoteControlError("invalid-session-name", "An agent session name is required.");

		const repository = await this.adapters.repositories.getByPath(input.repositoryPath);
		if (!repository) {
			throw new RemoteControlError(
				"repository-not-approved",
				`Repository is not approved for remote control: ${input.repositoryPath}`,
			);
		}

		const existing = await this.adapters.sessions.list();
		if (input.workspace && existing.some((session) => session.workspace === input.workspace)) {
			throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${input.workspace}`);
		}

		const workspace = input.workspace
			? await this.adapters.workspaces.adopt(input.workspace, input.branch)
			: await this.adapters.workspaces.create(repository, input.branch || `rc/${name}`);
		if (existing.some((session) => session.workspace === workspace.path)) {
			if (workspace.created) await this.adapters.workspaces.remove?.(workspace);
			throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${workspace.path}`);
		}

		let piSession: { id: string } | undefined;
		let topic: { id: string } | undefined;
		try {
			piSession = await this.adapters.pi.create({ name, repository, workspace });
			const sessionTopicName = topicTitle(repository.name, name, workspace.branch);
			topic = await this.adapters.telegram.createSessionTopic(sessionTopicName);
			const session: AgentSession = {
				id: id("session"), name, repositoryId: repository.id, repositoryPath: repository.path,
				workspace: workspace.path, branch: workspace.branch, piSessionId: piSession.id,
				topicId: topic.id, topicName: sessionTopicName,
				createdAt: this.now().toISOString(), status: "active",
			};
			await this.adapters.sessions.save(session);
			return session;
		} catch (error) {
			if (topic && this.adapters.telegram.removeTopic) await this.adapters.telegram.removeTopic(topic.id).catch(() => undefined);
			if (piSession && this.adapters.pi.remove) await this.adapters.pi.remove(piSession.id).catch(() => undefined);
			if (workspace.created && this.adapters.workspaces.remove) await this.adapters.workspaces.remove(workspace).catch(() => undefined);
			throw error;
		}
	}

	async sessionsByRepository(): Promise<Map<string, AgentSession[]>> {
		const grouped = new Map<string, AgentSession[]>();
		for (const session of await this.adapters.sessions.list()) {
			const sessions = grouped.get(session.repositoryPath) || [];
			sessions.push(session);
			grouped.set(session.repositoryPath, sessions);
		}
		return grouped;
	}

	async attach(idToAttach: string): Promise<AgentSession> {
		const session = await this.adapters.sessions.get(idToAttach);
		if (!session) throw new RemoteControlError("session-not-found", `Agent session not found: ${idToAttach}`);
		return session;
	}

	credentials(): CredentialStore {
		return this.adapters.credentials;
	}

	/** Serializes login, logout, start, and stop so the bridge is never started twice. */
	private withLifecycleLock<T>(operation: () => Promise<T>): Promise<T> {
		const previous = this.lifecycleTail;
		let release!: () => void;
		this.lifecycleTail = new Promise<void>((resolve) => { release = resolve; });
		return previous.then(operation).finally(release);
	}

	private async readCredentials(): Promise<RemoteControlCredentials | undefined> {
		const stored = await this.adapters.credentials.read();
		return isCredentials(stored) ? stored : undefined;
	}

	/**
	 * Local-only login: validates the BotFather token, then waits for the owner to
	 * send a one-time code in the private forum group. The sender becomes the only
	 * allowlisted user and the chat becomes the approved group.
	 */
	login(options: LoginOptions): Promise<RemoteControlCredentials> {
		return this.withLifecycleLock(async () => {
			await this.stopLocked();
			const token = options.token.trim();
			if (!TOKEN_PATTERN.test(token)) throw new RemoteControlError("invalid-token", "That does not look like a BotFather token.");
			const api = this.adapters.telegramBot(token);
			const bot = await verifyToken(api);
			const previous = await this.readCredentials();

			const code = `rc-${randomBytes(4).toString("hex")}`;
			const deadline = AbortSignal.timeout(options.timeoutMs ?? LOGIN_TIMEOUT_MS);
			// stop(), logout(), and Pi shutdown cancel a pending handshake rather than wait for it.
			const cancel = new AbortController();
			this.pendingLogin = cancel;
			const signal = AbortSignal.any([deadline, cancel.signal, ...(options.signal ? [options.signal] : [])]);
			let offset = await drainUpdates(api);
			await options.onHandshakeCode(code, bot);

			let handshake: TelegramMessage | undefined;
			try {
				while (!handshake) {
					let updates: TelegramUpdate[];
					try {
						signal.throwIfAborted();
						updates = await api.getUpdates({ offset, timeoutSeconds: POLL_TIMEOUT_SECONDS, signal });
					} catch (error) {
						if (cancel.signal.aborted) throw new RemoteControlError("login-cancelled", "Remote control login was cancelled.");
						if (deadline.aborted) throw new RemoteControlError("login-timeout", "No login code arrived from Telegram in time.");
						throw error;
					}
					for (const update of updates) {
						offset = update.updateId + 1;
						const message = update.message;
						if (!message?.text?.trim().split(/\s+/).includes(code)) continue;
						if (message.senderChatId === message.chat.id) throw new RemoteControlError("anonymous-owner", ANONYMOUS_OWNER_MESSAGE);
						if (message.from && !message.from.isBot) handshake = message;
					}
				}
			} finally {
				this.pendingLogin = undefined;
			}
			// Acknowledge the handshake so the bridge never replays it.
			await api.getUpdates({ offset, timeoutSeconds: 0 });

			const owner = handshake.from!;
			const chat = handshake.chat.type === "private" ? handshake.chat : await api.getChat(handshake.chat.id);
			await verifyGroup(api, chat, bot.id, owner.id);

			const confirmation = `Remote control linked to @${owner.username ?? owner.id}. Start it locally with /rc.`;
			let controlTopicId = previous?.group.id === chat.id ? previous.group.controlTopicId : undefined;
			if (controlTopicId !== undefined) {
				// The previous control topic may have been deleted; fall back to a new one.
				await api.sendMessage({ chatId: chat.id, threadId: controlTopicId, text: confirmation }).catch(() => { controlTopicId = undefined; });
			}
			if (controlTopicId === undefined) {
				try {
					controlTopicId = (await api.createForumTopic(chat.id, CONTROL_TOPIC_NAME)).threadId;
					await api.sendMessage({ chatId: chat.id, threadId: controlTopicId, text: confirmation });
				} catch (error) {
					throw new RemoteControlError("invalid-group", `The bot could not create or post in a topic: ${errorMessage(error)}`);
				}
			}

			const credentials: RemoteControlCredentials = {
				version: 1,
				botToken: token,
				bot: { id: bot.id, username: bot.username },
				owner: { id: owner.id, username: owner.username },
				group: { id: chat.id, title: chat.title, controlTopicId },
				authenticatedAt: this.now().toISOString(),
			};
			await this.adapters.credentials.write(credentials);
			return credentials;
		});
	}

	/** Stops the bridge and removes local credentials. Revoking the token itself is a BotFather operation. */
	logout(): Promise<{ wasRunning: boolean; hadCredentials: boolean }> {
		this.pendingLogin?.abort();
		return this.withLifecycleLock(async () => {
			const wasRunning = await this.stopLocked();
			// An unreadable credentials file still counts as present and must still be removed.
			const hadCredentials = await this.adapters.credentials.read().then((stored) => stored !== undefined, () => true);
			await this.adapters.credentials.clear();
			return { wasRunning, hadCredentials };
		});
	}

	/**
	 * Starts the remote bridge as a long-polling task inside the current process.
	 * It runs until stop(), logout(), or process shutdown; nothing outlives Pi.
	 * With `options.session`, the current Pi conversation is exposed in its session topic first.
	 */
	start(options: StartOptions = {}): Promise<{ alreadyRunning: boolean; credentials: RemoteControlCredentials; session?: AgentSession }> {
		return this.withLifecycleLock(async () => {
			if (this.bridge) {
				const [route] = this.bridge.routes.values();
				return { alreadyRunning: true, credentials: this.bridge.credentials, session: route?.session };
			}
			const credentials = await this.readCredentials();
			if (!credentials) throw new RemoteControlError("not-logged-in", "Remote control is not logged in; run /rc login locally.");

			const api = this.adapters.telegramBot(credentials.botToken);
			const bot = await verifyToken(api);
			let chat: TelegramChat;
			try {
				chat = await api.getChat(credentials.group.id);
			} catch (error) {
				throw new RemoteControlError("invalid-group", `The bot can no longer access the approved group: ${errorMessage(error)}`);
			}
			await verifyGroup(api, chat, bot.id, credentials.owner.id);
			const offset = await drainUpdates(api);

			const live = options.session;
			const session = live ? await this.withCreationLock(() => this.exposeLocked(api, credentials, live, options)) : undefined;
			const abort = new AbortController();
			const bridge: Bridge = { abort, done: Promise.resolve(), credentials, api, options, routes: new Map() };
			if (session && live) {
				const threadId = Number(session.topicId);
				bridge.routes.set(threadId, { session, threadId, pi: live, outbox: Promise.resolve() });
			}
			this.bridge = bridge;
			bridge.done = this.poll(bridge, offset);
			await api.sendMessage({ chatId: credentials.group.id, threadId: credentials.group.controlTopicId, text: "Remote control started." })
				.catch((error) => options.onError?.(error));
			return { alreadyRunning: false, credentials, session };
		});
	}

	/**
	 * Makes the live Pi conversation the agent session for its workspace. A workspace
	 * already exposed by an earlier conversation keeps its topic, which is rebound to
	 * this conversation and renamed if the session name or branch changed.
	 */
	private async exposeLocked(api: TelegramBotApi, credentials: RemoteControlCredentials, live: LivePiSession, options: StartOptions): Promise<AgentSession> {
		const repository = await this.registerRepositoryLocked(live.repositoryPath);
		const existing = (await this.adapters.sessions.list()).find((session) => session.workspace === live.workspace);
		const name = live.name.trim() || existing?.name || DEFAULT_SESSION_NAME;
		const title = topicTitle(repository.name, name, live.branch);
		const chatId = credentials.group.id;
		const connected = `Connected to Pi session "${name}" on ${live.branch}. ${SESSION_TOPIC_HELP}`;

		// Posting proves the stored topic still exists; one deleted in Telegram is replaced.
		// Any other failure fails the start rather than orphaning a topic that still exists.
		let threadId = existing ? Number(existing.topicId) : undefined;
		if (threadId !== undefined) {
			await api.sendMessage({ chatId, threadId, text: connected }).catch((error) => {
				if (!isMissingTopic(error)) throw error;
				threadId = undefined;
			});
		}
		if (threadId === undefined) {
			threadId = (await api.createForumTopic(chatId, title)).threadId;
			await api.sendMessage({ chatId, threadId, text: connected });
		} else if (existing?.topicName !== title) {
			await api.editForumTopic({ chatId, threadId, name: title }).catch((error) => options.onDeliveryError?.(error));
		}

		const session: AgentSession = {
			id: existing?.id ?? id("session"),
			name,
			repositoryId: repository.id,
			repositoryPath: repository.path,
			workspace: live.workspace,
			branch: live.branch,
			piSessionId: live.id,
			topicId: String(threadId),
			topicName: title,
			createdAt: existing?.createdAt ?? this.now().toISOString(),
			status: "active",
		};
		if (existing) await this.adapters.sessions.update(session);
		else await this.adapters.sessions.save(session);
		return session;
	}

	/** Stops accepting remote messages and cancels a pending login. Returns whether the bridge was running. */
	stop(): Promise<boolean> {
		this.pendingLogin?.abort();
		return this.withLifecycleLock(() => this.stopLocked());
	}

	private async stopLocked(): Promise<boolean> {
		const bridge = this.bridge;
		if (!bridge) return false;
		this.bridge = undefined;
		bridge.abort.abort();
		await bridge.done;
		const chatId = bridge.credentials.group.id;
		for (const [threadId, route] of bridge.routes) {
			clearTimeout(route.progress?.timer);
			await route.outbox;
			await bridge.api.sendMessage({ chatId, threadId, text: "Disconnected: remote control stopped." }).catch(() => undefined);
		}
		await bridge.api
			.sendMessage({ chatId, threadId: bridge.credentials.group.controlTopicId, text: "Remote control stopped." })
			.catch(() => undefined);
		return true;
	}

	status(): RemoteControlStatus {
		const credentials = this.bridge?.credentials;
		return {
			running: this.bridge !== undefined,
			bot: credentials?.bot.username && `@${credentials.bot.username}`,
			group: credentials?.group.title,
			topics: [...(this.bridge?.routes.values() ?? [])].map((route) => route.session.topicName),
		};
	}

	/** Reads the stored login without contacting Telegram. */
	async loginStatus(): Promise<{ loggedIn: boolean; bot?: string; group?: string }> {
		const credentials = await this.readCredentials();
		if (!credentials) return { loggedIn: false };
		return { loggedIn: true, bot: credentials.bot.username && `@${credentials.bot.username}`, group: credentials.group.title };
	}

	/**
	 * Reports what a live Pi session is doing to its session topic: one editable
	 * progress message per run of work, then the condensed final response. Ignored
	 * unless the running bridge exposes that session.
	 */
	recordActivity(piSessionId: string, activity: PiActivity): void {
		const bridge = this.bridge;
		const route = bridge && [...bridge.routes.values()].find((candidate) => candidate.pi.id === piSessionId);
		if (!bridge || !route) return;

		switch (activity.type) {
			case "run-start": {
				if (route.progress) {
					route.progress.prompt ??= activity.prompt;
					this.scheduleProgressEdit(bridge, route);
				} else {
					this.beginProgress(bridge, route, activity.prompt);
				}
				return;
			}
			case "tool-start": {
				const progress = route.progress ?? this.beginProgress(bridge, route);
				progress.tools.push({ id: activity.toolCallId, label: describeTool(activity.toolName, activity.args), state: "running" });
				this.scheduleProgressEdit(bridge, route);
				return;
			}
			case "tool-end": {
				const tool = route.progress?.tools.find((candidate) => candidate.id === activity.toolCallId);
				if (!tool) return;
				tool.state = activity.isError ? "failed" : "done";
				this.scheduleProgressEdit(bridge, route);
				return;
			}
			case "response": {
				const failure = activity.aborted ? "⚠️ Run aborted." : activity.error ? failureText(activity.error) : undefined;
				if (failure && route.progress) {
					route.progress.failure = failure;
					return;
				}
				if (route.progress) route.progress.failure = undefined;
				const text = failure ?? condenseForTelegram(activity.text);
				if (text) this.reply(bridge, route, text);
				return;
			}
			case "settled": {
				const progress = route.progress;
				if (!progress) return;
				route.progress = undefined;
				clearTimeout(progress.timer);
				if (progress.failure) this.reply(bridge, route, progress.failure);
				this.post(bridge, route, () => this.showProgress(bridge, route, progress, progress.failure ? "failed" : "done"));
				return;
			}
		}
	}

	private beginProgress(bridge: Bridge, route: Route, prompt?: string): Progress {
		const progress: Progress = { startedAt: this.now().getTime(), prompt, tools: [] };
		route.progress = progress;
		this.post(bridge, route, () => this.showProgress(bridge, route, progress));
		return progress;
	}

	/** Coalesces progress changes into at most one edit per interval. */
	private scheduleProgressEdit(bridge: Bridge, route: Route): void {
		const progress = route.progress;
		if (!progress || progress.timer) return;
		progress.timer = setTimeout(() => {
			progress.timer = undefined;
			if (route.progress === progress) this.post(bridge, route, () => this.showProgress(bridge, route, progress));
		}, this.progressIntervalMs);
	}

	/** Sends the progress message on first use and edits it in place afterwards. */
	private async showProgress(bridge: Bridge, route: Route, progress: Progress, finished?: "done" | "failed"): Promise<void> {
		const text = renderProgress({ prompt: progress.prompt, tools: progress.tools, elapsedMs: this.now().getTime() - progress.startedAt, finished });
		if (text === progress.shown) return;
		const chatId = bridge.credentials.group.id;
		if (progress.messageId === undefined) progress.messageId = (await bridge.api.sendMessage({ chatId, threadId: route.threadId, text })).messageId;
		else await bridge.api.editMessageText({ chatId, messageId: progress.messageId, text });
		progress.shown = text;
	}

	/** Queues a Telegram call for a session topic; failures are reported, never thrown. */
	private post(bridge: Bridge, route: Route, send: () => Promise<void>): void {
		route.outbox = route.outbox
			.then(() => withRateLimitRetry(send, bridge.abort.signal))
			.catch((error) => bridge.options.onDeliveryError?.(error));
	}

	private reply(bridge: Bridge, route: Route, text: string): void {
		this.post(bridge, route, async () => {
			await bridge.api.sendMessage({ chatId: bridge.credentials.group.id, threadId: route.threadId, text });
		});
	}

	/** Delivers an owner message from a session topic to its live Pi session. */
	private deliver(bridge: Bridge, route: Route, text: string): void {
		const input = parseSessionTopicInput(text);
		if (input.kind === "invalid") return this.reply(bridge, route, input.reply);
		if (route.pi.isIdle()) return route.pi.prompt(input.text);
		if (input.kind === "followUp") {
			route.pi.followUp(input.text);
			return this.reply(bridge, route, "Queued as a follow-up after the current run.");
		}
		route.pi.steer(input.text);
		this.reply(bridge, route, "Steering the current run.");
	}

	private async poll(bridge: Bridge, initialOffset: number | undefined): Promise<void> {
		const { api, credentials, options } = bridge;
		const signal = bridge.abort.signal;
		let offset = initialOffset;
		let retryDelay = 1000;
		let failing = false;
		const rejected = new Set<string>();
		const reject = async (message: TelegramMessage, key: string, text: string) => {
			if (rejected.has(key)) return;
			rejected.add(key);
			await api.sendMessage({ chatId: message.chat.id, threadId: message.threadId, text });
		};

		while (!signal.aborted) {
			let updates: TelegramUpdate[];
			try {
				updates = await api.getUpdates({ offset, timeoutSeconds: POLL_TIMEOUT_SECONDS, signal });
				retryDelay = 1000;
				if (failing) options.onRecovered?.();
				failing = false;
			} catch (error) {
				if (signal.aborted) return;
				const fatal = fatalPollError(error);
				if (fatal) {
					if (this.bridge === bridge) this.bridge = undefined;
					for (const route of bridge.routes.values()) clearTimeout(route.progress?.timer);
					options.onStopped?.(fatal);
					return;
				}
				// Network or Telegram outages never stop the bridge; retry with backoff.
				failing = true;
				options.onError?.(error);
				await sleep(retryDelay, signal);
				retryDelay = Math.min(retryDelay * 2, MAX_RETRY_DELAY_MS);
				continue;
			}
			for (const update of updates) {
				if (signal.aborted) return;
				offset = update.updateId + 1;
				const message = update.message;
				if (!message?.from) continue;
				try {
					if (message.chat.id === credentials.group.id && message.senderChatId === credentials.group.id) {
						await reject(message, "anonymous", ANONYMOUS_OWNER_MESSAGE);
					} else if (message.from.isBot) {
						continue;
					} else if (message.from.id !== credentials.owner.id) {
						await reject(message, `user:${message.from.id}`, "Not authorized: this bot only accepts its owner.");
					} else if (message.chat.id !== credentials.group.id) {
						await reject(message, `chat:${message.chat.id}`, "Remote control only accepts messages in the approved forum group.");
					} else if (message.text) {
						const route = message.threadId === undefined ? undefined : bridge.routes.get(message.threadId);
						if (route) {
							this.deliver(bridge, route, message.text);
						} else if (message.threadId !== undefined && message.threadId !== credentials.group.controlTopicId) {
							await reject(message, `topic:${message.threadId}`, "This topic is not connected to a running Pi session.");
						} else {
							await options.onMessage?.({ messageId: message.messageId, threadId: message.threadId, text: message.text });
						}
					}
				} catch (error) {
					options.onError?.(error);
				}
			}
		}
	}
}
