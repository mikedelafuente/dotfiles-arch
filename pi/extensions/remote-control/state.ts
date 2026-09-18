/** Machine-local JSON adapters for remote-control state. Do not symlink this file into dotfiles. */
import { chmod, mkdir, readFile, rename, rm, unlink, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { dirname } from "node:path";
import { RemoteControlError, type AgentSession, type AgentSessionStore, type CredentialStore, type Repository, type RepositoryRegistry } from "./coordinator.ts";

type State = { repositories: Repository[]; sessions: AgentSession[] };

export class JsonStateStore {
	private readonly path: string;
	constructor(path: string) { this.path = path; }

	async read(): Promise<State> {
		try {
			return JSON.parse(await readFile(this.path, "utf8")) as State;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") return { repositories: [], sessions: [] };
			throw error;
		}
	}

	async write(state: State): Promise<void> {
		const directory = dirname(this.path);
		await mkdir(directory, { recursive: true, mode: 0o700 });
		await chmod(directory, 0o700);
		const temporary = `${this.path}.tmp-${randomUUID()}`;
		await writeFile(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600, flag: "wx" });
		await chmod(temporary, 0o600);
		await rename(temporary, this.path);
	}

	async update(mutator: (state: State) => void): Promise<void> {
		const lock = `${this.path}.lock`;
		for (;;) {
			try {
				await mkdir(lock, { recursive: false, mode: 0o700 });
				break;
			} catch (error) {
				if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
				await new Promise((resolve) => setTimeout(resolve, 10));
			}
		}
		try { const state = await this.read(); mutator(state); await this.write(state); }
		finally { await rm(lock, { recursive: true, force: true }); }
	}
}

export class JsonRepositoryRegistry implements RepositoryRegistry {
	private readonly store: JsonStateStore;
	constructor(store: JsonStateStore) { this.store = store; }
	async getByPath(path: string): Promise<Repository | undefined> { return (await this.store.read()).repositories.find((item) => item.path === path); }
	async list(): Promise<Repository[]> { return (await this.store.read()).repositories; }
	async register(repository: Repository): Promise<void> {
		await this.store.update((state) => {
			if (!state.repositories.some((item) => item.path === repository.path)) state.repositories.push(repository);
		});
	}
	async remove(path: string): Promise<void> { const state = await this.store.read(); state.repositories = state.repositories.filter((item) => item.path !== path); await this.store.write(state); }
}

export class JsonAgentSessionStore implements AgentSessionStore {
	private readonly store: JsonStateStore;
	constructor(store: JsonStateStore) { this.store = store; }
	async list(): Promise<AgentSession[]> { return (await this.store.read()).sessions; }
	async get(id: string): Promise<AgentSession | undefined> { return (await this.store.read()).sessions.find((item) => item.id === id); }
	async save(session: AgentSession): Promise<void> {
		await this.store.update((state) => {
			if (state.sessions.some((item) => item.workspace === session.workspace)) {
				throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${session.workspace}`);
			}
			state.sessions.push(session);
		});
	}
	async update(session: AgentSession): Promise<void> {
		await this.store.update((state) => {
			const index = state.sessions.findIndex((item) => item.id === session.id);
			if (index === -1) throw new RemoteControlError("session-not-found", `Agent session not found: ${session.id}`);
			if (state.sessions.some((item) => item.id !== session.id && item.workspace === session.workspace)) {
				throw new RemoteControlError("duplicate-workspace", `Workspace is already assigned: ${session.workspace}`);
			}
			state.sessions[index] = session;
		});
	}
}

export class JsonCredentialStore implements CredentialStore {
	private readonly path: string;
	constructor(path: string) { this.path = path; }
	async read(): Promise<unknown | undefined> {
		try { return JSON.parse(await readFile(this.path, "utf8")); }
		catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw error; }
	}
	async write(credentials: unknown): Promise<void> {
		const directory = dirname(this.path);
		await mkdir(directory, { recursive: true, mode: 0o700 });
		await chmod(directory, 0o700);
		const temporary = `${this.path}.tmp-${randomUUID()}`;
		await writeFile(temporary, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600, flag: "wx" });
		await chmod(temporary, 0o600);
		await rename(temporary, this.path);

	}
	async clear(): Promise<void> { try { await unlink(this.path); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; } }
}
