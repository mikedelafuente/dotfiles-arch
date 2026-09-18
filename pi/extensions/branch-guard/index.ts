/**
 * Branch Guard extension
 *
 * Prevents agent file edits on the main branch by moving the work to an
 * existing local branch or creating a new one first.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);

const MUTATING_TOOLS = new Set(["edit", "write"]);
const MAIN_BRANCHES = new Set(["main", "master"]);

function defaultBranchName(cwd: string): string {
	const repoName = cwd.split("/").filter(Boolean).pop()?.replace(/[^a-zA-Z0-9._-]+/g, "-") || "work";
	const timestamp = new Date().toISOString().replace(/[-:TZ.]/g, "").slice(0, 14);
	return `work/${repoName}-${timestamp}`;
}

async function git(cwd: string, args: string[]): Promise<string> {
	const result = await execFileAsync("git", ["-C", cwd, ...args], { encoding: "utf8" });
	return result.stdout.trim();
}

async function localBranches(cwd: string): Promise<string[]> {
	const output = await git(cwd, ["branch", "--format=%(refname:short)"]);
	return output
		.split("\n")
		.map((branch) => branch.trim())
		.filter((branch) => branch && !MAIN_BRANCHES.has(branch));
}

async function switchBranch(cwd: string, branch: string, create: boolean): Promise<void> {
	if (!/^[\w./-]+$/.test(branch) || branch.startsWith("-") || branch.endsWith("/")) {
		throw new Error(`Invalid branch name: ${branch}`);
	}
	await git(cwd, create ? ["switch", "-c", branch] : ["switch", branch]);
}

export default function branchGuardExtension(pi: ExtensionAPI): void {
	let transition: Promise<{ allowed: boolean; reason?: string }> | undefined;

	pi.on("tool_call", async (event, ctx) => {
		if (!MUTATING_TOOLS.has(event.toolName)) return;
		if (!ctx.hasUI) return { block: true, reason: "Cannot modify files on main without interactive branch selection." };

		if (transition) return (await transition).allowed ? undefined : transition.then((result) => ({ block: true, reason: result.reason }));

		transition = (async () => {
			try {
				try {
					if ((await git(ctx.cwd, ["rev-parse", "--is-inside-work-tree"])) !== "true") {
						return { allowed: true };
					}
				} catch {
					// File edits outside a Git worktree are not protected by this guard.
					return { allowed: true };
				}

				const branch = await git(ctx.cwd, ["branch", "--show-current"]);
				if (!MAIN_BRANCHES.has(branch)) return { allowed: true };

				const branches = await localBranches(ctx.cwd);
				let selected: string;
				let create = false;

				if (branches.length === 0) {
					selected = defaultBranchName(ctx.cwd);
					create = true;
					ctx.ui.notify(`On ${branch}; creating ${selected} before editing.`, "info");
				} else {
					const createOption = "Create a new branch";
					const choice = await ctx.ui.select("You are on main. Switch to a branch before editing:", [
						...branches,
						createOption,
					]);
					if (!choice) return { allowed: false, reason: "Branch selection cancelled; edit blocked on main." };
					if (choice === createOption) {
						selected = (await ctx.ui.input("New branch name", defaultBranchName(ctx.cwd)))?.trim() || "";
						create = true;
					} else {
						selected = choice;
					}
				}

				if (!selected) return { allowed: false, reason: "No branch selected; edit blocked on main." };
				await switchBranch(ctx.cwd, selected, create);
				ctx.ui.notify(`Switched to ${selected}.`, "info");
				return { allowed: true };
			} catch (error) {
				const reason = error instanceof Error ? error.message : String(error);
				return { allowed: false, reason: `Could not leave main; edit blocked: ${reason}` };
			}
		})();

		try {
			const result = await transition;
			return result.allowed ? undefined : { block: true, reason: result.reason };
		} finally {
			transition = undefined;
		}
	});
}
