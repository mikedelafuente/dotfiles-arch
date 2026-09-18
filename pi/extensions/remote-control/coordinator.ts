/**
 * Remote-control domain seam.
 *
 * This module deliberately knows nothing about Telegram, Pi RPC, or Git. Those
 * concerns are adapters so coordinator behavior can be tested with fakes.
 */

import { randomBytes, randomUUID } from "node:crypto";

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
	sendMessage(input: { chatId: number; threadId?: number; text: string }): Promise<void>;
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

export type StartOptions = {
	onMessage?(message: AuthorizedMessage): Promise<void>;
	/** A recoverable failure; polling retries with backoff. */
	onError?(error: unknown): void;
	/** Polling works again after one or more onError calls. */
	onRecovered?(): void;
	/** The bridge stopped itself because retrying cannot succeed. */
	onStopped?(reason: RemoteControlError): void;
};

export type RemoteControlStatus = {
	running: boolean;
	bot?: string;
	group?: string;
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

function topicName(repository: Repository, sessionName: string, branch: string): string {
	return `${repository.name} / ${sessionName} / ${branch}`;
}

/** The single authority for repository and agent-session invariants. */
export class RemoteControlCoordinator {
	private creationTail: Promise<void> = Promise.resolve();
	private bridge?: { abort: AbortController; done: Promise<void>; credentials: RemoteControlCredentials; api: TelegramBotApi };
	private lifecycleTail: Promise<void> = Promise.resolve();
	private pendingLogin?: AbortController;

	private readonly adapters: RemoteControlAdapters;
	private readonly now: () => Date;

	constructor(adapters: RemoteControlAdapters, now = () => new Date()) {
		this.adapters = adapters;
		this.now = now;
	}

	private withCreationLock<T>(operation: () => Promise<T>): Promise<T> {
		const previous = this.creationTail;
		let release!: () => void;
		this.creationTail = new Promise<void>((resolve) => { release = resolve; });
		return previous.then(operation).finally(release);
	}

	registerRepository(path: string, name = path.split("/").filter(Boolean).pop() || path): Promise<Repository> {
		return this.withCreationLock(async () => {
			const existing = await this.adapters.repositories.getByPath(path);
			if (existing) return existing;
			const repository: Repository = { id: id("repo"), path, name, registeredAt: this.now().toISOString() };
			await this.adapters.repositories.register(repository);
			return repository;
		});
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
			const sessionTopicName = topicName(repository, name, workspace.branch);
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
	 */
	start(options: StartOptions = {}): Promise<{ alreadyRunning: boolean; credentials: RemoteControlCredentials }> {
		return this.withLifecycleLock(async () => {
			if (this.bridge) return { alreadyRunning: true, credentials: this.bridge.credentials };
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

			const abort = new AbortController();
			const bridge = { abort, done: Promise.resolve(), credentials, api };
			this.bridge = bridge;
			bridge.done = this.poll(api, credentials, offset, abort.signal, options);
			await api.sendMessage({ chatId: credentials.group.id, threadId: credentials.group.controlTopicId, text: "Remote control started." })
				.catch((error) => options.onError?.(error));
			return { alreadyRunning: false, credentials };
		});
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
		await bridge.api
			.sendMessage({ chatId: bridge.credentials.group.id, threadId: bridge.credentials.group.controlTopicId, text: "Remote control stopped." })
			.catch(() => undefined);
		return true;
	}

	status(): RemoteControlStatus {
		const credentials = this.bridge?.credentials;
		return {
			running: this.bridge !== undefined,
			bot: credentials?.bot.username && `@${credentials.bot.username}`,
			group: credentials?.group.title,
		};
	}

	/** Reads the stored login without contacting Telegram. */
	async loginStatus(): Promise<{ loggedIn: boolean; bot?: string; group?: string }> {
		const credentials = await this.readCredentials();
		if (!credentials) return { loggedIn: false };
		return { loggedIn: true, bot: credentials.bot.username && `@${credentials.bot.username}`, group: credentials.group.title };
	}

	private async poll(
		api: TelegramBotApi,
		credentials: RemoteControlCredentials,
		initialOffset: number | undefined,
		signal: AbortSignal,
		options: StartOptions,
	): Promise<void> {
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
					if (this.bridge?.abort.signal === signal) this.bridge = undefined;
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
						await options.onMessage?.({ messageId: message.messageId, threadId: message.threadId, text: message.text });
					}
				} catch (error) {
					options.onError?.(error);
				}
			}
		}
	}
}
