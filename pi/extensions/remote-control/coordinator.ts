/**
 * Remote-control domain seam.
 *
 * This module deliberately knows nothing about Telegram, Pi RPC, or Git. Those
 * concerns are adapters so coordinator behavior can be tested with fakes.
 */

import { randomBytes, randomUUID } from "node:crypto";
import {
	condenseForTelegram,
	describeOpenIn,
	describeTool,
	errorMessage,
	failureText,
	parseControlCommand,
	parseSessionTopicInput,
	renderProgress,
	renderSessions,
	sessionBranch,
	SESSION_TOPIC_HELP,
	topicTitle,
	type ControlCommand,
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
	/** The Pi session file, used to resume the conversation and to check its history still exists. */
	piSessionFile?: string;
	topicId: string;
	topicName: string;
	createdAt: string;
	/** Started by `/rc new` and not answered yet: Pi writes no history file before the first response. */
	unprompted?: boolean;
	/** Conversations this workspace ran before a later one took over its topic; attachable by Pi session id. */
	earlierConversations?: EarlierConversation[];
};

/** The Pi conversation fields an agent session stores for its current conversation and its earlier ones. */
export type PiConversation = Pick<AgentSession, "piSessionId" | "piSessionFile" | "name" | "branch">;

/** A Pi conversation an agent session ran before a later conversation took over its workspace and topic. */
export type EarlierConversation = PiConversation & { replacedAt: string };

/**
 * How an agent session stands, computed rather than stored: `active` sessions are
 * routed by the running bridge, `disconnected` ones can be attached, `open` ones are
 * held by a Pi remote control is not routing, `stale` ones lost their Pi history,
 * and `missing-workspace` ones lost their worktree.
 */
export type SessionStatus = "active" | "disconnected" | "open" | "stale" | "missing-workspace";

/** A live Pi process holding a conversation; `here` is this Pi. */
export type LeaseHolder = { pid: number; here: boolean };

/** A status, with the Pi processes holding the conversation when it is `open`. */
type Standing<Status extends SessionStatus> = { status: Status; openIn?: LeaseHolder[] };

/** Where a conversation that is not connected here stands. */
type Health = Standing<Exclude<SessionStatus, "active">>;

export type EarlierConversationOverview = EarlierConversation & Health;

export type SessionOverview = Omit<AgentSession, "earlierConversations"> & Standing<SessionStatus> & {
	earlierConversations: EarlierConversationOverview[];
};

export type RepositorySessions = { repository: { name: string; path: string }; sessions: SessionOverview[] };

export type NewSessionInput = {
	name: string;
	/**
	 * The local conversation `/rc new` was run from. On a feature branch or in a
	 * linked worktree it is adopted; on the main line a new workspace is created in its repository.
	 */
	current?: LivePiSession;
	/** A registered repository's name or path, for remote requests. */
	repository?: string;
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
	/** Creates a worktree on a new branch from the repository's main line. */
	create(repository: Repository, branch: string): Promise<Workspace>;
	/**
	 * Removes a worktree `create` made, and its branch; only used to roll back a
	 * failed creation. Rejects with an error naming what it could not remove.
	 */
	remove(workspace: Workspace, repository: Repository): Promise<void>;
	/** The branch checked out in a workspace, or undefined when the workspace no longer exists. */
	inspect(path: string): Promise<{ branch: string } | undefined>;
	/** The branch new work in the repository starts from, such as `main`. */
	mainLine(repositoryPath: string): Promise<string>;
}

export type PiSessionEvents = {
	activity(activity: PiActivity): void;
	/** The Pi process ended without `close()`. */
	exited(reason: string): void;
};

/** A Pi conversation remote control runs in its own Pi process, in its own workspace. */
export interface AgentProcess extends LivePiSession {
	close(): Promise<void>;
}

export interface PiSessionAdapter {
	/** Starts a new, named Pi conversation in the workspace. */
	create(input: { name: string; repository: Repository; workspace: Workspace }, events: PiSessionEvents): Promise<AgentProcess>;
	/**
	 * Starts Pi on the session's persisted conversation; rejects rather than start a
	 * different one. An `unprompted` session without history restarts under its own id.
	 */
	resume(session: AgentSession, events: PiSessionEvents): Promise<AgentProcess>;
	/** Whether the session's Pi history still exists to resume. */
	hasHistory(session: AgentSession): Promise<boolean>;
}

/**
 * Which processes have a Pi conversation open. Pi does not lock session files, so
 * every Pi running this extension leases its current conversation; two Pi
 * processes appending to one session file corrupt it.
 */
export interface SessionLeases {
	/** Live Pi processes holding the conversation, including this one; stale leases are dropped. */
	holders(piSessionId: string): Promise<LeaseHolder[]>;
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
	deleteForumTopic(input: { chatId: number; threadId: number }): Promise<void>;
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
	/** The checked-out branch, or `detached@<commit>` for a detached HEAD. */
	readonly branch: string;
	/** The repository to approve: the main checkout when `workspace` is a linked worktree. */
	readonly repositoryPath: string;
	/** The Pi session file, once Pi knows it. */
	readonly sessionFile?: string;
	isIdle(): boolean;
	/** Starts a run with a new user message. */
	prompt(text: string): void;
	/** Redirects the current run. */
	steer(text: string): void;
	/** Queues a user message for after the current run. */
	followUp(text: string): void;
	/** Sets the Pi session name, when an adopted conversation is renamed. */
	rename?(name: string): void;
}

/** What a live Pi session is doing, reported to its session topic. Tool output is deliberately absent. */
export type PiActivity =
	| { type: "run-start"; prompt?: string }
	| { type: "tool-start"; toolCallId: string; toolName: string; args: unknown }
	| { type: "tool-end"; toolCallId: string; isError: boolean }
	| { type: "response"; text: string; error?: string; aborted?: boolean }
	/** Pi will not continue on its own: no retry, compaction, or queued follow-up is left. */
	| { type: "settled" }
	/** Something the owner should know that is not part of a run, posted as is. */
	| { type: "notice"; text: string };

export type StartOptions = {
	/** The current Pi conversation to expose; omitted outside a Git repository. */
	session?: LivePiSession;
	/** Owner messages that are neither for an agent session nor a control-topic `/rc` command. */
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
	leases: SessionLeases;
	credentials: CredentialStore;
	telegramBot(token: string): TelegramBotApi;
};

export class RemoteControlError extends Error {
	readonly code:
		| "repository-not-approved"
		| "duplicate-workspace"
		| "duplicate-session"
		| "session-not-found"
		| "ambiguous-session"
		| "missing-workspace"
		| "stale-session"
		| "session-in-use"
		| "rollback-incomplete"
		| "not-running"
		| "invalid-session-name"
		| "invalid-token"
		| "invalid-group"
		| "login-timeout"
		| "login-cancelled"
		| "anonymous-owner"
		| "bridge-conflict"
		| "not-logged-in";

	constructor(code: RemoteControlError["code"], message: string, options?: ErrorOptions) {
		super(message, options);
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
/** The last path segment, as a repository's display name. */
function nameFromPath(path: string): string {
	return path.split("/").filter(Boolean).pop() || path;
}

function connectedText(name: string, branch: string): string {
	return `Connected to Pi session "${name}" on ${branch}. ${SESSION_TOPIC_HELP}`;
}

/** A stored session as it would be with `conversation` as its current Pi conversation. */
function withConversation(session: AgentSession, conversation: PiConversation): AgentSession {
	const { earlierConversations: _earlier, unprompted: _unprompted, ...rest } = session;
	return { ...rest, name: conversation.name, branch: conversation.branch, piSessionId: conversation.piSessionId, piSessionFile: conversation.piSessionFile };
}

function conversationOf(session: AgentSession): PiConversation {
	return { piSessionId: session.piSessionId, piSessionFile: session.piSessionFile, name: session.name, branch: session.branch };
}

/** A session to attach: its current conversation, or one of its earlier ones. */
type AttachTarget = { session: AgentSession; earlier?: EarlierConversation };

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
	/** Serializes control-topic commands so their replies stay in order. */
	control: Promise<void>;
};

/** The single authority for repository and agent-session invariants. */
export class RemoteControlCoordinator {
	private creationTail: Promise<void> = Promise.resolve();
	private bridge?: Bridge;
	private lifecycleTail: Promise<void> = Promise.resolve();
	private pendingLogin?: AbortController;
	/** Pi processes remote control started, keyed by agent session id. They outlive `/rc stop` but not `shutdown()`. */
	private readonly agents = new Map<string, { session: AgentSession; pi: AgentProcess }>();
	/** Exits reported while an agent was still being connected, which must fail its creation or attach. */
	private readonly exitedBeforeConnect = new WeakMap<AgentProcess, string>();

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

	private async registerRepositoryLocked(path: string, name = nameFromPath(path)): Promise<Repository> {
		const existing = await this.adapters.repositories.getByPath(path);
		if (existing) return existing;
		const repository: Repository = { id: id("repo"), path, name, registeredAt: this.now().toISOString() };
		await this.adapters.repositories.register(repository);
		return repository;
	}

	listRepositories(): Promise<Repository[]> {
		return this.adapters.repositories.list();
	}

	/**
	 * Starts a named agent session. Run locally from a feature branch or a linked
	 * worktree, it adopts that workspace and the current conversation; otherwise it
	 * creates a worktree, branch, Pi session, and session topic together, or none of them.
	 */
	newSession(input: NewSessionInput): Promise<{ session: AgentSession; adopted: boolean }> {
		return this.withCreationLock(async () => {
			const bridge = this.requireBridge();
			const name = input.name.trim();
			if (!name) throw new RemoteControlError("invalid-session-name", "An agent session name is required.");
			const current = input.current;
			if (current && (await this.isAdoptable(current))) {
				const session = await this.exposeLocked(bridge, current, name);
				current.rename?.(name);
				return { session, adopted: true };
			}
			const repository = current
				? await this.registerRepositoryLocked(current.repositoryPath)
				: await this.approvedRepository(input.repository ?? "");
			return { session: await this.createLocked(bridge, repository, name), adopted: false };
		});
	}

	/** A linked worktree, or a named branch other than the main line: `/rc new` works there instead of in a new worktree. */
	private async isAdoptable(live: LivePiSession): Promise<boolean> {
		if (live.workspace !== live.repositoryPath) return true;
		if (live.branch.startsWith("detached@")) return false;
		return live.branch !== (await this.adapters.workspaces.mainLine(live.repositoryPath));
	}

	private requireBridge(): Bridge {
		if (!this.bridge) throw new RemoteControlError("not-running", "Remote control is not running; start it locally with /rc.");
		return this.bridge;
	}

	/** Finds a registered repository by name or path. Remote requests can never register one. */
	private async approvedRepository(reference: string): Promise<Repository> {
		const repositories = await this.adapters.repositories.list();
		const found = repositories.find((repository) => repository.path === reference)
			?? repositories.find((repository) => repository.name.toLowerCase() === reference.toLowerCase());
		if (found) return found;
		const approved = repositories.map((repository) => repository.name).join(", ") || "none yet; run /rc in a repository locally";
		throw new RemoteControlError("repository-not-approved", `Repository is not approved for remote control: ${reference}. Approved: ${approved}.`);
	}

	private async createLocked(bridge: Bridge, repository: Repository, name: string): Promise<AgentSession> {
		const branch = sessionBranch(name);
		if (!branch) throw new RemoteControlError("invalid-session-name", `Use letters or digits in the session name: ${name}`);
		const existing = await this.adapters.sessions.list();
		const namesake = existing.find((session) => session.repositoryPath === repository.path && sessionBranch(session.name) === branch);
		if (namesake) {
			throw new RemoteControlError("duplicate-session", `${repository.name} already has an agent session named ${namesake.name}; use /rc attach ${namesake.name}.`);
		}

		const workspace = await this.adapters.workspaces.create(repository, branch);
		const chatId = bridge.credentials.group.id;
		const title = topicTitle(repository.name, name, workspace.branch);
		let agent: AgentProcess | undefined;
		let threadId: number | undefined;
		try {
			if (existing.some((session) => session.workspace === workspace.path)) {
				throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${workspace.path}`);
			}
			agent = await this.adapters.pi.create({ name, repository, workspace }, this.agentEvents(() => agent));
			threadId = (await bridge.api.createForumTopic(chatId, title)).threadId;
			await bridge.api.sendMessage({ chatId, threadId, text: connectedText(name, workspace.branch) });
			const session: AgentSession = {
				id: id("session"), name, repositoryId: repository.id, repositoryPath: repository.path,
				workspace: workspace.path, branch: workspace.branch, piSessionId: agent.id, piSessionFile: agent.sessionFile,
				topicId: String(threadId), topicName: title, createdAt: this.now().toISOString(), unprompted: true,
			};
			await this.adapters.sessions.save(session);
			this.connectAgent(session, agent);
			return session;
		} catch (error) {
			// Undo every step even when one fails, and name what could not be undone.
			const leftovers: string[] = [];
			// `what` is omitted when the step's own error already names what remains.
			const undo = (step: () => Promise<void>, what?: string) =>
				step().catch((failure) => { leftovers.push(what ? `${what}: ${errorMessage(failure)}` : errorMessage(failure)); });
			const createdTopic = threadId;
			const startedAgent = agent;
			if (createdTopic !== undefined) {
				await undo(() => bridge.api.deleteForumTopic({ chatId, threadId: createdTopic }), `session topic "${title}" (${createdTopic})`);
			}
			if (startedAgent) await undo(() => startedAgent.close(), `Pi process of ${name}`);
			if (workspace.created) await undo(() => this.adapters.workspaces.remove(workspace, repository));
			if (!leftovers.length) throw error;
			throw new RemoteControlError("rollback-incomplete", `${errorMessage(error).replace(/\.?$/, ".")} Rollback left behind: ${leftovers.join("; ")}.`, { cause: error });
		}
	}

	/** Relays a Pi process's activity to its topic and notices when it exits on its own. */
	private agentEvents(agent: () => AgentProcess | undefined): PiSessionEvents {
		return {
			activity: (activity) => {
				const current = agent();
				if (!current) return;
				if (activity.type === "run-start") this.markPrompted(current);
				this.recordActivity(current.id, activity);
			},
			exited: (reason) => {
				const current = agent();
				if (current && !this.disconnectAgent(current, reason)) this.exitedBeforeConnect.set(current, reason);
			},
		};
	}

	/**
	 * An agent started its first run: Pi is about to write its history, so from now on
	 * a missing history means it was lost, and attach must not restart it empty.
	 */
	private markPrompted(agent: AgentProcess): void {
		const entry = [...this.agents.values()].find((candidate) => candidate.pi === agent);
		if (!entry?.session.unprompted) return;
		delete entry.session.unprompted;
		this.withCreationLock(async () => {
			const stored = await this.adapters.sessions.get(entry.session.id);
			if (!stored?.unprompted || stored.piSessionId !== agent.id) return;
			delete stored.unprompted;
			await this.adapters.sessions.update(stored);
		}).catch((error) => this.bridge?.options.onError?.(error));
	}

	/** Keeps a running agent and routes its topic while the bridge runs, including after a restart. */
	private connectAgent(session: AgentSession, agent: AgentProcess): void {
		const exit = this.exitedBeforeConnect.get(agent);
		if (exit !== undefined) throw new Error(`Pi ${exit}`);
		this.agents.set(session.id, { session, pi: agent });
		const bridge = this.bridge;
		if (bridge) this.route(bridge, session, agent);
	}

	private route(bridge: Bridge, session: AgentSession, pi: LivePiSession): void {
		for (const [threadId, route] of bridge.routes) {
			if (route.session.id === session.id || route.pi === pi) {
				clearTimeout(route.progress?.timer);
				bridge.routes.delete(threadId);
			}
		}
		const threadId = Number(session.topicId);
		bridge.routes.set(threadId, { session, threadId, pi, outbox: Promise.resolve() });
	}

	/** Returns false for an agent that was never connected. */
	private disconnectAgent(agent: AgentProcess, reason: string): boolean {
		const entry = [...this.agents].find(([, candidate]) => candidate.pi === agent);
		if (!entry) return false;
		this.agents.delete(entry[0]);
		const bridge = this.bridge;
		const route = bridge && [...bridge.routes.values()].find((candidate) => candidate.pi === agent);
		if (!bridge || !route) return true;
		bridge.routes.delete(route.threadId);
		clearTimeout(route.progress?.timer);
		this.reply(bridge, route, `Disconnected: the Pi agent ${reason}. Reconnect with /rc attach ${route.session.name}.`);
		return true;
	}

	/** Agent sessions grouped by repository, each with its computed status. */
	async sessions(): Promise<RepositorySessions[]> {
		const connected = this.connectedSessionIds();
		const repositories = await this.adapters.repositories.list();
		const groups = new Map<string, RepositorySessions>();
		for (const repository of repositories) groups.set(repository.path, { repository: { name: repository.name, path: repository.path }, sessions: [] });
		for (const session of await this.adapters.sessions.list()) {
			let group = groups.get(session.repositoryPath);
			if (!group) {
				group = { repository: { name: nameFromPath(session.repositoryPath), path: session.repositoryPath }, sessions: [] };
				groups.set(session.repositoryPath, group);
			}
			const { earlierConversations = [], ...current } = session;
			const exists = (await this.adapters.workspaces.inspect(session.workspace)) !== undefined;
			const health = (conversation: AgentSession): Promise<Health> =>
				exists ? this.conversationHealth(conversation) : Promise.resolve({ status: "missing-workspace" });
			const earlier: EarlierConversationOverview[] = [];
			for (const conversation of earlierConversations) earlier.push({ ...conversation, ...(await health(withConversation(session, conversation))) });
			group.sessions.push({
				...current,
				...(connected.has(session.id) ? { status: "active" as const } : await health(session)),
				earlierConversations: earlier,
			});
		}
		return [...groups.values()].filter((group) => group.sessions.length);
	}

	private connectedSessionIds(): Set<string> {
		return new Set([...this.agents.keys(), ...[...this.bridge?.routes.values() ?? []].map((route) => route.session.id)]);
	}

	/** Why a conversation in an existing workspace, not connected here, can or cannot be attached. */
	private async conversationHealth(conversation: AgentSession): Promise<Health> {
		const openIn = await this.openIn(conversation.piSessionId);
		if (openIn.length) return { status: "open", openIn };
		if (!(await this.resumable(conversation))) return { status: "stale" };
		return { status: "disconnected" };
	}

	/** Pi can resume the conversation: its history exists, or it never had any to lose. */
	private async resumable(conversation: AgentSession): Promise<boolean> {
		return conversation.unprompted === true || this.adapters.pi.hasHistory(conversation);
	}

	private openIn(piSessionId: string): Promise<LeaseHolder[]> {
		return this.adapters.leases.holders(piSessionId);
	}

	/** Refuses a conversation another Pi has open: two Pi processes writing one session file corrupt it. */
	private async assertNotOpen(conversation: AgentSession, what: string): Promise<void> {
		const openIn = await this.openIn(conversation.piSessionId);
		if (!openIn.length) return;
		throw new RemoteControlError(
			"session-in-use",
			`${what} is open in ${describeOpenIn(openIn)}; close it there first, since two Pi processes writing one session file corrupt it.`,
		);
	}

	/**
	 * Finds a stored session by id, name, or id prefix, or one of its conversations
	 * by Pi session id or prefix. Earlier conversations can only be reached by Pi session id.
	 */
	private async findSession(reference: string): Promise<AttachTarget> {
		const wanted = reference.trim();
		const sessions = await this.adapters.sessions.list();
		const conversations: AttachTarget[] = sessions.flatMap((session) => [
			{ session },
			...(session.earlierConversations ?? []).map((earlier) => ({ session, earlier })),
		]);
		const piSessionId = (target: AttachTarget) => target.earlier?.piSessionId ?? target.session.piSessionId;
		const byId = sessions.find((session) => session.id === wanted || session.id === `session-${wanted}`);
		if (byId) return { session: byId };
		const byPiSessionId = conversations.find((target) => piSessionId(target) === wanted);
		if (byPiSessionId) return byPiSessionId;
		const byName: AttachTarget[] = sessions.filter((session) => session.name.toLowerCase() === wanted.toLowerCase()).map((session) => ({ session }));
		const byPrefix = () => conversations.filter((target) =>
			piSessionId(target).startsWith(wanted) || (!target.earlier && target.session.id.replace(/^session-/, "").startsWith(wanted)));
		const matches = byName.length ? byName : wanted.length >= 4 ? byPrefix() : [];
		if (matches.length === 1) return matches[0];
		if (matches.length > 1) {
			const choices = matches.map(({ session, earlier }) => earlier
				? `${earlier.piSessionId} (earlier conversation of ${session.name})`
				: `${session.id} (${session.repositoryPath}, ${session.branch})`).join("; ");
			throw new RemoteControlError("ambiguous-session", `More than one agent session matches ${wanted}; attach one by id: ${choices}.`);
		}
		throw new RemoteControlError("session-not-found", `Agent session not found: ${wanted}. List them with /rc sessions.`);
	}

	/**
	 * A session's earlier conversations once `next` becomes its current one: the
	 * displaced conversation joins them, and any without Pi history are dropped.
	 */
	private async earlierConversationsAfter(session: AgentSession, next: string): Promise<EarlierConversation[] | undefined> {
		if (session.piSessionId === next) return session.earlierConversations;
		const displaced: EarlierConversation = { ...conversationOf(session), replacedAt: this.now().toISOString() };
		const kept: EarlierConversation[] = [];
		for (const conversation of [...(session.earlierConversations ?? []), displaced]) {
			if (conversation.piSessionId === next) continue;
			if (await this.resumable(withConversation(session, conversation))) kept.push(conversation);
		}
		return kept.length ? kept : undefined;
	}

	/**
	 * Reconnects a persisted agent session: resumes its Pi conversation in its
	 * workspace and routes its topic again. Connected sessions are left as they are.
	 * Attaching an earlier conversation makes it the session's current one again.
	 * A conversation another Pi has open is refused.
	 */
	attach(reference: string): Promise<{ session: AgentSession; alreadyConnected: boolean }> {
		return this.withCreationLock(async () => {
			const bridge = this.requireBridge();
			const { session, earlier } = await this.findSession(reference);
			if (this.connectedSessionIds().has(session.id)) {
				if (!earlier) return { session, alreadyConnected: true };
				throw new RemoteControlError(
					"session-in-use",
					`The workspace of ${session.name} is in use by its connected conversation; two conversations never share a workspace.`,
				);
			}
			const repository = await this.adapters.repositories.getByPath(session.repositoryPath);
			if (!repository) {
				throw new RemoteControlError("repository-not-approved", `The repository of ${session.name} is no longer approved for remote control: ${session.repositoryPath}`);
			}
			const workspace = await this.adapters.workspaces.inspect(session.workspace);
			if (!workspace) {
				throw new RemoteControlError("missing-workspace", `The workspace of ${session.name} no longer exists: ${session.workspace}`);
			}
			const target = earlier ? withConversation(session, earlier) : session;
			if (earlier) await this.assertNotOpen(session, `The current conversation of ${session.name}`);
			await this.assertNotOpen(target, earlier ? `Conversation ${earlier.piSessionId} of ${session.name}` : session.name);
			if (!(await this.resumable(target))) {
				throw new RemoteControlError("stale-session", `The Pi history of ${target.name} was not found, so it cannot be resumed.`);
			}

			let agent: AgentProcess | undefined;
			agent = await this.adapters.pi.resume(target, this.agentEvents(() => agent));
			try {
				if (agent.id !== target.piSessionId) throw new Error(`Pi resumed session ${agent.id} instead of ${target.piSessionId}.`);
				const title = topicTitle(repository.name, target.name, workspace.branch);
				const threadId = await this.bindTopic(bridge, session, title, `Reconnected to Pi session "${target.name}" on ${workspace.branch}. ${SESSION_TOPIC_HELP}`);
				const attached: AgentSession = {
					...target, branch: workspace.branch, topicId: String(threadId), topicName: title,
					piSessionFile: agent.sessionFile ?? target.piSessionFile,
					earlierConversations: await this.earlierConversationsAfter(session, target.piSessionId),
				};
				await this.adapters.sessions.update(attached);
				this.connectAgent(attached, agent);
				return { session: attached, alreadyConnected: false };
			} catch (error) {
				await agent.close().catch(() => undefined);
				throw error;
			}
		});
	}

	/**
	 * Announces a session in its stored topic, renaming it when the title changed.
	 * Posting proves the topic still exists; one deleted in Telegram is replaced. Any
	 * other failure is thrown rather than orphaning a topic that still exists.
	 */
	private async bindTopic(bridge: Bridge, stored: AgentSession | undefined, title: string, text: string): Promise<number> {
		const { api, options } = bridge;
		const chatId = bridge.credentials.group.id;
		let threadId = stored ? Number(stored.topicId) : undefined;
		if (threadId !== undefined) {
			await api.sendMessage({ chatId, threadId, text }).catch((error) => {
				if (!isMissingTopic(error)) throw error;
				threadId = undefined;
			});
		}
		if (threadId === undefined) {
			threadId = (await api.createForumTopic(chatId, title)).threadId;
			await api.sendMessage({ chatId, threadId, text });
		} else if (stored?.topicName !== title) {
			await api.editForumTopic({ chatId, threadId, name: title }).catch((error) => options.onDeliveryError?.(error));
		}
		return threadId;
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
			const bridge: Bridge = {
				abort: new AbortController(), done: Promise.resolve(), credentials, api, options, routes: new Map(), control: Promise.resolve(),
			};
			const session = await this.withCreationLock(async () => {
				const exposed = live ? await this.exposeLocked(bridge, live) : undefined;
				for (const agent of this.agents.values()) {
					this.route(bridge, agent.session, agent.pi);
					this.reply(bridge, bridge.routes.get(Number(agent.session.topicId))!, `Remote control resumed. ${SESSION_TOPIC_HELP}`);
				}
				this.bridge = bridge;
				return exposed;
			});
			bridge.done = this.poll(bridge, offset);
			await api.sendMessage({ chatId: credentials.group.id, threadId: credentials.group.controlTopicId, text: "Remote control started." })
				.catch((error) => options.onError?.(error));
			return { alreadyRunning: false, credentials, session };
		});
	}

	/**
	 * Makes a live Pi conversation the agent session for its workspace and routes its
	 * topic. A workspace already exposed by an earlier conversation keeps its topic,
	 * which is rebound to this conversation and renamed if the name or branch changed.
	 */
	private async exposeLocked(bridge: Bridge, live: LivePiSession, requestedName?: string): Promise<AgentSession> {
		const owner = [...this.agents.values()].find((agent) => agent.session.workspace === live.workspace);
		if (owner) {
			throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned to the running agent session ${owner.session.name}: ${live.workspace}`);
		}
		const repository = await this.registerRepositoryLocked(live.repositoryPath);
		const existing = (await this.adapters.sessions.list()).find((session) => session.workspace === live.workspace);
		const name = requestedName ?? (live.name.trim() || existing?.name || DEFAULT_SESSION_NAME);
		const title = topicTitle(repository.name, name, live.branch);
		const threadId = await this.bindTopic(bridge, existing, title, connectedText(name, live.branch));

		// A different conversation takes the topic over; the one it replaces stays attachable.
		const earlierConversations = existing && (await this.earlierConversationsAfter(existing, live.id));
		const session: AgentSession = {
			id: existing?.id ?? id("session"),
			name,
			repositoryId: repository.id,
			repositoryPath: repository.path,
			workspace: live.workspace,
			branch: live.branch,
			piSessionId: live.id,
			piSessionFile: live.sessionFile,
			topicId: String(threadId),
			topicName: title,
			createdAt: existing?.createdAt ?? this.now().toISOString(),
			...(existing?.piSessionId === live.id && existing.unprompted ? { unprompted: true } : {}),
			...(earlierConversations ? { earlierConversations } : {}),
		};
		if (existing) await this.adapters.sessions.update(session);
		else await this.adapters.sessions.save(session);
		this.route(bridge, session, live);
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
			const text = this.agents.has(route.session.id)
				? "Disconnected: remote control stopped. This agent keeps running and reconnects when /rc starts again."
				: "Disconnected: remote control stopped.";
			await bridge.api.sendMessage({ chatId, threadId, text }).catch(() => undefined);
		}
		await bridge.api
			.sendMessage({ chatId, threadId: bridge.credentials.group.controlTopicId, text: "Remote control stopped." })
			.catch(() => undefined);
		return true;
	}

	/** Pi shutdown: stops the bridge and every Pi process remote control started, so nothing outlives Pi. */
	shutdown(): Promise<void> {
		this.pendingLogin?.abort();
		return this.withLifecycleLock(async () => {
			await this.stopLocked();
			// Waits for a creation in flight, whose process would otherwise be left running.
			await this.withCreationLock(async () => {
				const agents = [...this.agents.values()];
				this.agents.clear();
				await Promise.all(agents.map((agent) => agent.pi.close().catch(() => undefined)));
			});
		});
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
			case "notice": {
				this.reply(bridge, route, condenseForTelegram(activity.text));
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

	/** Runs a control-topic command in the background, so polling continues, and replies where it was sent. */
	private runControl(bridge: Bridge, threadId: number | undefined, command: ControlCommand): void {
		const send = (text: string) => bridge.api.sendMessage({ chatId: bridge.credentials.group.id, threadId, text });
		bridge.control = bridge.control
			.then(async () => {
				let reply: string;
				try {
					reply = await this.controlReply(command);
				} catch (error) {
					reply = `Failed: ${errorMessage(error)}`;
				}
				await send(reply);
			})
			.catch((error) => bridge.options.onError?.(error));
	}

	private async controlReply(command: ControlCommand): Promise<string> {
		switch (command.kind) {
			case "invalid":
				return command.reply;
			case "sessions":
				return renderSessions(await this.sessions());
			case "new": {
				const { session } = await this.newSession({ name: command.name, repository: command.repository });
				return `Started ${session.name} in topic "${session.topicName}", working in ${session.workspace}.`;
			}
			case "attach": {
				const { session, alreadyConnected } = await this.attach(command.session);
				return alreadyConnected
					? `${session.name} is already connected in topic "${session.topicName}".`
					: `Reconnected ${session.name} in topic "${session.topicName}".`;
			}
		}
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
							const command = parseControlCommand(message.text);
							if (command) this.runControl(bridge, message.threadId, command);
							else await options.onMessage?.({ messageId: message.messageId, threadId: message.threadId, text: message.text });
						}
					}
				} catch (error) {
					options.onError?.(error);
				}
			}
		}
	}
}
