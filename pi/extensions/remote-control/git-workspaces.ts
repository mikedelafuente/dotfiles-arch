/** Git worktrees as remote-control workspaces. */
import { execFile } from "node:child_process";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";
import type { BranchState, Repository, Workspace, WorkspaceAdapter } from "./coordinator.ts";
import { errorMessage } from "./messages.ts";

const execFileAsync = promisify(execFile);

async function git(cwd: string, args: string[]): Promise<string> {
	try {
		const result = await execFileAsync("git", ["-C", cwd, ...args], { encoding: "utf8" });
		return result.stdout.trim();
	} catch (error) {
		const stderr = (error as { stderr?: string }).stderr?.trim();
		throw new Error(stderr || errorMessage(error));
	}
}

/** The checked-out branch, or `detached@<commit>` for a detached HEAD. */
async function currentBranch(cwd: string): Promise<string> {
	return await git(cwd, ["branch", "--show-current"])
		|| `detached@${await git(cwd, ["rev-parse", "--short", "HEAD"]).catch(() => "unborn")}`;
}

/** The worktree, branch, and main repository `cwd` belongs to, or undefined outside Git. */
export async function gitWorkspace(cwd: string): Promise<{ workspace: string; branch: string; repositoryPath: string } | undefined> {
	let workspace: string;
	try {
		workspace = await git(cwd, ["rev-parse", "--show-toplevel"]);
	} catch {
		return undefined;
	}
	if (!workspace) return undefined;
	const commonDir = await git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
	return { workspace, branch: await currentBranch(cwd), repositoryPath: basename(commonDir) === ".git" ? dirname(commonDir) : commonDir };
}

/** The branch new work starts from: the remote's default branch when known, else main or master, else HEAD. */
async function mainLine(repository: string): Promise<string> {
	const remoteHead = await git(repository, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]).catch(() => "");
	const candidates = [remoteHead.replace(/^origin\//, ""), "main", "master"].filter(Boolean);
	for (const branch of candidates) {
		if (await git(repository, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`]).then(() => true, () => false)) return branch;
	}
	return "HEAD";
}

/** A merged pull request from a branch, with the commit it merged. */
export type MergedPullRequest = { number: number; headOid: string };

export type GitWorkspacesOptions = {
	/** Finds a merged pull request from `branch`; the default asks the authenticated `gh` CLI. */
	mergedPullRequest?(repositoryPath: string, branch: string): Promise<MergedPullRequest | undefined>;
};

/** The latest merged pull request from `branch`, through `gh`; undefined when there is none or `gh` cannot tell. */
async function ghMergedPullRequest(repositoryPath: string, branch: string): Promise<MergedPullRequest | undefined> {
	try {
		const { stdout } = await execFileAsync(
			"gh",
			["pr", "list", "--head", branch, "--state", "merged", "--json", "number,headRefOid", "--limit", "1"],
			{ cwd: repositoryPath, encoding: "utf8", timeout: 15_000 },
		);
		const [pullRequest] = JSON.parse(stdout) as { number: number; headRefOid: string }[];
		return pullRequest && { number: pullRequest.number, headOid: pullRequest.headRefOid };
	} catch {
		return undefined;
	}
}

/** Worktrees live beside the repository, in `<repository>.worktrees/<branch>`, so they stay visible and outside it. */
export class GitWorkspaces implements WorkspaceAdapter {
	private readonly mergedPullRequest: NonNullable<GitWorkspacesOptions["mergedPullRequest"]>;

	constructor(options: GitWorkspacesOptions = {}) {
		this.mergedPullRequest = options.mergedPullRequest ?? ghMergedPullRequest;
	}

	async create(repository: Repository, branch: string): Promise<Workspace> {
		const path = join(`${repository.path}.worktrees`, branch.replace(/\//g, "-"));
		await git(repository.path, ["worktree", "add", "--quiet", "-b", branch, path, await mainLine(repository.path)]);
		return { path, branch, created: true };
	}

	/**
	 * Rejects naming what remains: the branch cannot be deleted while its worktree is still there.
	 * The branch is deleted with `-D`, since a squash-merged branch is never merged as far as Git knows.
	 */
	async remove(workspace: Workspace, repository: Repository, { discardChanges = true }: { discardChanges?: boolean } = {}): Promise<void> {
		// A cleanup may find either one already gone: a worktree deleted by hand, or a branch deleted or detached from.
		if (await this.inspect(workspace.path)) {
			await git(repository.path, ["worktree", "remove", ...(discardChanges ? ["--force"] : []), workspace.path]).catch((error) => {
				throw new Error(`worktree ${workspace.path}${workspace.branch ? ` and branch ${workspace.branch}` : ""} remain: ${errorMessage(error)}`);
			});
		} else {
			await git(repository.path, ["worktree", "prune"]).catch(() => undefined);
		}
		if (!workspace.branch || !(await git(repository.path, ["rev-parse", "--verify", "--quiet", `refs/heads/${workspace.branch}`]).then(() => true, () => false))) return;
		await git(repository.path, ["branch", "-D", workspace.branch]).catch((error) => {
			throw new Error(`branch ${workspace.branch} remains: ${errorMessage(error)}`);
		});
	}

	async changes(path: string): Promise<string[]> {
		const status = await git(path, ["status", "--porcelain", "--untracked-files=all"]);
		return status ? status.split("\n") : [];
	}

	async branchState(repositoryPath: string, branch: string): Promise<BranchState | undefined> {
		const tip = await git(repositoryPath, ["rev-parse", "--verify", "--quiet", `refs/heads/${branch}`]).catch(() => "");
		if (!tip) return undefined;
		const main = await mainLine(repositoryPath);
		const unmergedCommits = Number(await git(repositoryPath, ["rev-list", "--count", `${main}..${tip}`]));
		if (!unmergedCommits) return { mainLine: main, merged: true, unmergedCommits };
		// A squash merge leaves the branch out of the main line's history; its pull request counts only if it merged this tip.
		const pullRequest = await this.mergedPullRequest(repositoryPath, branch);
		return pullRequest?.headOid === tip
			? { mainLine: main, merged: true, pullRequest: pullRequest.number, unmergedCommits }
			: { mainLine: main, merged: false, unmergedCommits };
	}

	mainLine(repositoryPath: string): Promise<string> {
		return mainLine(repositoryPath);
	}

	async inspect(path: string): Promise<{ branch: string } | undefined> {
		const found = await gitWorkspace(path).catch(() => undefined);
		return found?.workspace === path ? { branch: found.branch } : undefined;
	}
}
