import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
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

const commit = (cwd: string, message: string) => git(cwd, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", message);

test("lists a workspace's uncommitted changes, untracked files included", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const workspace = await workspaces.create(repo, "rc/dirty");
	assert.deepEqual(await workspaces.changes(workspace.path), []);

	await writeFile(join(workspace.path, "notes.txt"), "draft\n");
	assert.deepEqual(await workspaces.changes(workspace.path), ["?? notes.txt"]);
});

test("a branch is merged once the main line contains it, or once its pull request merged at its tip", async (t) => {
	const repo = await repository(t);
	let pullRequest: { number: number; headOid: string } | undefined;
	const asked: string[] = [];
	const workspaces = new GitWorkspaces({
		mergedPullRequest: async (repositoryPath, branch) => { asked.push(`${repositoryPath} ${branch}`); return pullRequest; },
	});
	const workspace = await workspaces.create(repo, "rc/work");
	assert.deepEqual(await workspaces.branchState(repo.path, "rc/work"), { mainLine: "main", merged: true, unmergedCommits: 0 });

	await commit(workspace.path, "work");
	assert.deepEqual(await workspaces.branchState(repo.path, "rc/work"), { mainLine: "main", merged: false, unmergedCommits: 1 });
	assert.deepEqual(asked, [`${repo.path} rc/work`]);

	// A squash merge leaves the branch out of main's history; its merged pull request counts, but only at the branch's tip.
	const tip = await git(repo.path, "rev-parse", "rc/work");
	pullRequest = { number: 12, headOid: tip };
	assert.deepEqual(await workspaces.branchState(repo.path, "rc/work"), { mainLine: "main", merged: true, pullRequest: 12, unmergedCommits: 1 });
	await commit(workspace.path, "after the merge");
	assert.deepEqual(await workspaces.branchState(repo.path, "rc/work"), { mainLine: "main", merged: false, unmergedCommits: 2 });

	await git(repo.path, "branch", "-f", "main", "rc/work");
	assert.deepEqual(await workspaces.branchState(repo.path, "rc/work"), { mainLine: "main", merged: true, unmergedCommits: 0 });
	assert.equal(await workspaces.branchState(repo.path, "rc/none"), undefined);
});

test("removing a workspace without discarding changes refuses one with uncommitted work", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const workspace = await workspaces.create(repo, "rc/keep");
	await writeFile(join(workspace.path, "notes.txt"), "draft\n");

	await assert.rejects(workspaces.remove(workspace, repo, { discardChanges: false }), /worktree .* and branch rc\/keep remain/);
	assert.deepEqual(await workspaces.inspect(workspace.path), { branch: "rc/keep" });

	await workspaces.remove(workspace, repo, { discardChanges: true });
	assert.equal(await workspaces.inspect(workspace.path), undefined);
	assert.equal(await git(repo.path, "branch", "--list", "rc/keep"), "");
});

test("removing a workspace whose worktree is already gone deletes just its branch, and one with no branch just its worktree", async (t) => {
	const repo = await repository(t);
	const workspaces = new GitWorkspaces();
	const gone = await workspaces.create(repo, "rc/gone");
	await rm(gone.path, { recursive: true, force: true });
	await workspaces.remove(gone, repo, { discardChanges: false });
	assert.equal(await git(repo.path, "branch", "--list", "rc/gone"), "");

	const detached = await workspaces.create(repo, "rc/detached");
	await git(detached.path, "switch", "-q", "--detach");
	await git(repo.path, "branch", "-D", "rc/detached");
	await workspaces.remove({ ...detached, branch: "" }, repo, { discardChanges: false });
	assert.equal(await workspaces.inspect(detached.path), undefined);
});
