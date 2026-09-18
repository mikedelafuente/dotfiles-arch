import assert from "node:assert/strict";
import test from "node:test";
import { RemoteControlCoordinator, type AgentSession, type RemoteControlAdapters, type Repository, type Workspace } from "./coordinator.ts";

function fakes(): RemoteControlAdapters {
	const repositories: Repository[] = [];
	const sessions: AgentSession[] = [];
	const topics: string[] = [];
	return {
		repositories: {
			getByPath: async (path) => repositories.find((item) => item.path === path),
			list: async () => repositories,
			register: async (repository) => { repositories.push(repository); },
			remove: async (path) => { repositories.splice(repositories.findIndex((item) => item.path === path), 1); },
		},
		sessions: {
			list: async () => sessions,
			get: async (id) => sessions.find((item) => item.id === id),
			save: async (session) => { sessions.push(session); },
			update: async (session) => { sessions[sessions.findIndex((item) => item.id === session.id)] = session; },
		},
		workspaces: {
			create: async (_repository, branch): Promise<Workspace> => ({ path: `/tmp/${branch}`, branch, created: true }),
			adopt: async (path, branch = "existing"): Promise<Workspace> => ({ path, branch, created: false }),
		},
		pi: { create: async ({ name }) => ({ id: `pi-${name}` }) },
		telegram: { createSessionTopic: async (name) => { topics.push(name); return { id: `topic-${topics.length}` }; } },
		credentials: { read: async () => undefined, write: async () => undefined, clear: async () => undefined },
		telegramBot: () => { throw new Error("Telegram is not used by these tests"); },
	};
}

test("requires an approved repository and keeps session relationships together", async () => {
	const adapters = fakes();
	const coordinator = new RemoteControlCoordinator(adapters, () => new Date("2025-01-01T00:00:00Z"));
	await assert.rejects(() => coordinator.createSession({ name: "agent", repositoryPath: "/repo" }), { code: "repository-not-approved" });
	await coordinator.registerRepository("/repo", "demo");
	const session = await coordinator.createSession({ name: "agent", repositoryPath: "/repo", branch: "rc/agent" });
	assert.equal(session.repositoryPath, "/repo");
	assert.equal(session.workspace, "/tmp/rc/agent");
	assert.equal(session.branch, "rc/agent");
	assert.equal(session.topicName, "demo / agent / rc/agent");
	assert.equal(session.piSessionId, "pi-agent");
});

test("rejects concurrent sessions claiming one workspace", async () => {
	const adapters = fakes();
	const coordinator = new RemoteControlCoordinator(adapters);
	await coordinator.registerRepository("/repo");
	const first = coordinator.createSession({ name: "one", repositoryPath: "/repo", workspace: "/shared" });
	const second = coordinator.createSession({ name: "two", repositoryPath: "/repo", workspace: "/shared" });
	await first;
	await assert.rejects(second, { code: "duplicate-workspace" });
});

test("groups sessions by approved repository and can attach persisted sessions", async () => {
	const adapters = fakes();
	const coordinator = new RemoteControlCoordinator(adapters);
	await coordinator.registerRepository("/repo");
	const session = await coordinator.createSession({ name: "agent", repositoryPath: "/repo" });
	assert.equal((await coordinator.sessionsByRepository()).get("/repo")?.[0].id, session.id);
	assert.equal((await coordinator.attach(session.id)).piSessionId, session.piSessionId);
});
