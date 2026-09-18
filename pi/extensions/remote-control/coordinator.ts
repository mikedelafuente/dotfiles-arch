/**
 * Remote-control domain seam.
 *
 * This module deliberately knows nothing about Telegram, Pi RPC, or Git. Those
 * concerns are adapters so coordinator behavior can be tested with fakes.
 */

import { randomUUID } from "node:crypto";

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

export type RemoteControlAdapters = {
	repositories: RepositoryRegistry;
	sessions: AgentSessionStore;
	workspaces: WorkspaceAdapter;
	pi: PiSessionAdapter;
	telegram: TelegramTransport;
	credentials: CredentialStore;
};

export class RemoteControlError extends Error {
	readonly code:
		| "repository-not-approved"
		| "duplicate-workspace"
		| "session-not-found"
		| "invalid-session-name";

	constructor(code: RemoteControlError["code"], message: string) {
		super(message);
		this.name = "RemoteControlError";
		this.code = code;
	}
}

function id(prefix: string): string {
	return `${prefix}-${randomUUID()}`;
}

function topicName(repository: Repository, sessionName: string, branch: string): string {
	return `${repository.name} / ${sessionName} / ${branch}`;
}

/** The single authority for repository and agent-session invariants. */
export class RemoteControlCoordinator {
	private creationTail: Promise<void> = Promise.resolve();

	constructor(private readonly adapters: RemoteControlAdapters, private readonly now = () => new Date()) {}

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
}
