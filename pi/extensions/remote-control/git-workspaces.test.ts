import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import type { Repository } from "./coordinator.ts";
import { GitWorkspaces, gitWorkspace } from "./git-workspaces.ts";

const run = promisify(execFile);
const git = async (cwd: string, ...args: string[]) => (await run("git", ["-C", cwd, ...args], { encoding: "utf8" })).stdout.trim();

/** A repository with one commit on `main`, checked out on a feature branch. */
async function repository(t: test.TestContext): Promise<Repository> {
	const root = await realpath(await mkdtemp(join(tmpdir(), "rc-git-")));
	t.after(() => rm(root, { recursive: true, force: true }));
	const path = join(root, "demo");
	await run("git", ["init", "-q", "-b", "main", path]);
	await git(path, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init");
	await git(path, "switch", "-q", "-c", "feat/elsewhere");
	await git(path, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "feature");
	return { id: "repo-1", path, name: "demo", registeredAt: "2026-01-01T00:00:00Z" };
}

test("creates a sibling worktree on a new branch from the main line", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const workspace = await workspaces.create(repo, "rc/fix-ci");

	assert.deepEqual(workspace, { path: `${repo.path}.worktrees/rc-fix-ci`, branch: "rc/fix-ci", created: true });
	assert.equal(await git(workspace.path, "branch", "--show-current"), "rc/fix-ci");
	assert.equal(await git(workspace.path, "rev-parse", "HEAD"), await git(repo.path, "rev-parse", "main"), "branched from main, not the checked-out feature");
	assert.deepEqual(await workspaces.inspect(workspace.path), { branch: "rc/fix-ci" });
	assert.deepEqual(await gitWorkspace(workspace.path), { workspace: workspace.path, branch: "rc/fix-ci", repositoryPath: repo.path });
});

test("refuses a branch that already exists instead of reusing it", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	await assert.rejects(workspaces.create(repo, "feat/elsewhere"), /already exists/);
});

test("rolling back removes the worktree and its branch", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const workspace = await workspaces.create(repo, "rc/tmp");
	await workspaces.remove(workspace, repo);

	assert.equal(await workspaces.inspect(workspace.path), undefined);
	assert.equal(await git(repo.path, "branch", "--list", "rc/tmp"), "");
	assert.doesNotMatch(await git(repo.path, "worktree", "list"), /rc-tmp/);
});

test("inspect reports missing workspaces and directories that are no longer a worktree root", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	assert.equal(await workspaces.inspect(join(repo.path, "nope")), undefined);
	assert.equal(await workspaces.inspect(join(repo.path, ".git")), undefined);
	await git(repo.path, "switch", "-q", "--detach");
	assert.match((await workspaces.inspect(repo.path))?.branch ?? "", /^detached@[0-9a-f]+$/);
	assert.equal(await gitWorkspace(tmpdir()), undefined);
});

test("a rollback that cannot remove the worktree or branch names what it left behind", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const locked = await workspaces.create(repo, "rc/locked");
	await git(repo.path, "worktree", "lock", locked.path);
	await assert.rejects(workspaces.remove(locked, repo), new RegExp(`worktree ${locked.path} and branch rc/locked remain: .*locked`));
	assert.deepEqual(await workspaces.inspect(locked.path), { branch: "rc/locked" });

	// The branch is also checked out elsewhere, so only the worktree can go.
	const shared = await workspaces.create(repo, "rc/shared");
	await git(repo.path, "worktree", "add", "--quiet", "--force", `${repo.path}.worktrees/other`, "rc/shared");
	await assert.rejects(workspaces.remove(shared, repo), /^Error: branch rc\/shared remains: /);
	assert.equal(await workspaces.inspect(shared.path), undefined);
});
