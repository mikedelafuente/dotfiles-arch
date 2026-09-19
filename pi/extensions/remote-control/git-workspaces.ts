/** Git worktrees as remote-control workspaces. */
import { execFile } from "node:child_process";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";
import type { Repository, Workspace, WorkspaceAdapter } from "./coordinator.ts";

const execFileAsync = promisify(execFile);

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

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

/** Worktrees live beside the repository, in `<repository>.worktrees/<branch>`, so they stay visible and outside it. */
export class GitWorkspaces implements WorkspaceAdapter {
	async create(repository: Repository, branch: string): Promise<Workspace> {
		const path = join(`${repository.path}.worktrees`, branch.replace(/\//g, "-"));
		await git(repository.path, ["worktree", "add", "--quiet", "-b", branch, path, await mainLine(repository.path)]);
		return { path, branch, created: true };
	}

	/** Rejects naming what remains: the branch cannot be deleted while its worktree is still there. */
	async remove(workspace: Workspace, repository: Repository): Promise<void> {
		await git(repository.path, ["worktree", "remove", "--force", workspace.path]).catch((error) => {
			throw new Error(`worktree ${workspace.path} and branch ${workspace.branch} remain: ${errorMessage(error)}`);
		});
		await git(repository.path, ["branch", "-D", workspace.branch]).catch((error) => {
			throw new Error(`branch ${workspace.branch} remains: ${errorMessage(error)}`);
		});
	}

	mainLine(repositoryPath: string): Promise<string> {
		return mainLine(repositoryPath);
	}

	async inspect(path: string): Promise<{ branch: string } | undefined> {
		const found = await gitWorkspace(path).catch(() => undefined);
		return found?.workspace === path ? { branch: found.branch } : undefined;
	}
}
