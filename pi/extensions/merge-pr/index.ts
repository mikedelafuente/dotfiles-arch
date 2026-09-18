/**
 * Merge PR extension
 *
 * Implements the "merge this" workflow: commit and push the current branch,
 * create a pull request, monitor it, merge with squash, confirm the merge, and
 * only then clean up branches and return to an up-to-date main branch.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	failedCheck,
	formatChecks as formatCheckSummary,
	getPullRequest,
	getPullRequestChecks,
	pendingCheck,
	type Check,
	type PullRequest,
} from "../pr-monitor/index.ts";
import { Static, Type } from "typebox";

const execFileAsync = promisify(execFile);
const GITHUB_CHECK_INTERVAL_MS = 10_000;
const DEFAULT_TIMEOUT_MINUTES = 30;
const MAIN_BRANCHES = new Set(["main", "master"]);

const mergePrSchema = Type.Object({
	commitMessage: Type.Optional(Type.String({ description: "Commit message; defaults to a generic feature message" })),
	prTitle: Type.Optional(Type.String({ description: "Pull request title; defaults to the commit subject" })),
	prBody: Type.Optional(Type.String({ description: "Pull request body" })),
	timeoutMinutes: Type.Optional(
		Type.Integer({ description: "Maximum time to wait for checks and merge (default: 30)", minimum: 1, default: 30 }),
	),
});

export type MergePrInput = Static<typeof mergePrSchema>;

type CommandError = Error & { stdout?: string; stderr?: string };
type MergeDetails = {
	status: "working" | "merged" | "failed";
	branch?: string;
	pr?: PullRequest;
	checks?: Check[];
	reason?: string;
};

async function command(command: string, args: string[], cwd: string): Promise<string> {
	const result = await execFileAsync(command, args, { cwd, encoding: "utf8" });
	return result.stdout.trim();
}

async function git(args: string[], cwd: string): Promise<string> {
	return command("git", args, cwd);
}

async function gh(args: string[], cwd: string): Promise<string> {
	return command("gh", args, cwd);
}

async function ghJson<T>(args: string[], cwd: string): Promise<T> {
	return JSON.parse(await gh(args, cwd)) as T;
}

function defaultBranchName(cwd: string): string {
	const repo = cwd.split("/").filter(Boolean).pop()?.replace(/[^a-zA-Z0-9._-]+/g, "-") || "work";
	const timestamp = new Date().toISOString().replace(/[-:TZ.]/g, "").slice(0, 14);
	return `work/${repo}-${timestamp}`;
}

async function waitFor(seconds: number, signal: AbortSignal | undefined): Promise<void> {
	await new Promise<void>((resolve, reject) => {
		const timer = setTimeout(resolve, seconds * 1000);
		if (!signal) return;
		if (signal.aborted) {
			clearTimeout(timer);
			reject(new Error("Merge workflow cancelled"));
			return;
		}
		signal.addEventListener(
			"abort",
			() => {
				clearTimeout(timer);
				reject(new Error("Merge workflow cancelled"));
			},
			{ once: true },
		);
	});
}

function toolResult(text: string, details: MergeDetails, isError = false) {
	return {
		content: [{ type: "text" as const, text }],
		details,
		...(isError ? { isError: true } : {}),
	};
}

export default function mergePrExtension(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "merge_this",
		label: "Merge This",
		description:
			"Commit and push the current work, create a PR, monitor it every 10 seconds, squash-merge it, confirm the merge, then clean up branches and return to up-to-date main.",
		promptSnippet: "Commit, monitor, squash-merge, and clean up this branch",
		promptGuidelines: [
			"Use merge_this when the user asks to merge this or otherwise requests the full branch-to-PR merge workflow.",
			"Do not use it for general PR status checks when no merge is requested.",
		],
		parameters: mergePrSchema,
		executionMode: "sequential",

		async execute(_toolCallId, params: MergePrInput, signal, onUpdate, ctx) {
			const timeoutMinutes = params.timeoutMinutes ?? DEFAULT_TIMEOUT_MINUTES;
			const startedAt = Date.now();
			let branch = "";
			let pr: PullRequest | undefined;

			const update = (text: string, details: MergeDetails) => onUpdate?.(toolResult(text, details));
			const timedOut = () => Date.now() - startedAt >= timeoutMinutes * 60_000;

			try {
				branch = await git(["branch", "--show-current"], ctx.cwd);
				if (!branch) throw new Error("Cannot merge from a detached HEAD.");
				if (MAIN_BRANCHES.has(branch)) {
					branch = defaultBranchName(ctx.cwd);
					await git(["switch", "-c", branch], ctx.cwd);
					ctx.ui.notify(`Created ${branch} for the merge workflow.`, "info");
				}

				const status = await git(["status", "--porcelain"], ctx.cwd);
				if (status) {
					await git(["add", "-A"], ctx.cwd);
					const message = params.commitMessage?.trim() || "feat: apply requested changes";
					await git(["commit", "-m", message], ctx.cwd);
				}

				const commitSubject = await git(["log", "-1", "--pretty=%s"], ctx.cwd);
				await git(["push", "--set-upstream", "origin", branch], ctx.cwd);
				const repo = await gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], ctx.cwd);
				const existing = await ghJson<{ number: number; title: string; url: string }[]>(
					["pr", "list", "--repo", repo, "--head", branch, "--state", "open", "--json", "number,title,url", "--limit", "1"],
					ctx.cwd,
				);

				if (existing.length > 0) {
					pr = await getPullRequest(String(existing[0].number), repo, undefined, ctx.cwd);
				} else {
					const title = params.prTitle?.trim() || commitSubject || "Changes from agent";
					const body = params.prBody?.trim() || "Created by the Pi merge workflow.";
					const url = await gh(
						["pr", "create", "--repo", repo, "--base", "main", "--head", branch, "--title", title, "--body", body],
						ctx.cwd,
					);
					pr = await getPullRequest(url, repo, undefined, ctx.cwd);
				}

				while (true) {
					if (signal?.aborted) throw new Error("Merge workflow cancelled");
					pr = await getPullRequest(String(pr.number), repo, signal, ctx.cwd);
					const checks = await getPullRequestChecks(String(pr.number), repo, signal, ctx.cwd);
					const failed = checks.find(failedCheck);

					if (pr.mergedAt) break;
					if (pr.state === "CLOSED") throw new Error("Pull request closed without merging.");
					if (failed) throw new Error(`Check failed: ${failed.name} (${failed.state || failed.bucket}).`);
					if (timedOut()) throw new Error(`Timed out after ${timeoutMinutes} minutes.`);

					const checksPending = checks.some(pendingCheck);
					const needsRebase = ["BEHIND", "DIRTY"].includes(pr.mergeStateStatus);
					const waiting = checksPending || ["UNKNOWN", "BLOCKED"].includes(pr.mergeStateStatus);
					if (needsRebase && !checksPending) {
						await gh(["pr", "update-branch", String(pr.number), "--repo", repo, "--rebase"], ctx.cwd);
						update(`PR #${pr.number} needed a rebase; rebased through gh. Waiting for checks again.`, { status: "working", branch, pr, checks });
					} else if (!waiting) {
						try {
							await gh(["pr", "merge", String(pr.number), "--repo", repo, "--squash"], ctx.cwd);
							update(`Requested squash merge for PR #${pr.number}. Confirming merge before cleanup.`, { status: "working", branch, pr, checks });
						} catch (error) {
							const message = error instanceof Error ? error.message : String(error);
							throw new Error(`Squash merge failed: ${message}`);
						}
					} else {
						update(`Waiting on PR #${pr.number}: ${pr.mergeStateStatus.toLowerCase()}, ${formatCheckSummary(checks)}. Next GitHub check in 10s.`, { status: "working", branch, pr, checks });
					}

					await waitFor(GITHUB_CHECK_INTERVAL_MS / 1000, signal)
				}

				pr = await getPullRequest(String(pr.number), repo, signal, ctx.cwd);
				if (!pr.mergedAt) throw new Error("Merge command returned, but GitHub did not confirm the PR as merged.");

				await gh(["api", "--method", "DELETE", `repos/${repo}/git/refs/heads/${branch}`], ctx.cwd).catch((error: CommandError) => {
					if (!error.stderr?.includes("Not Found") && !error.message.includes("404")) throw error;
				});
				await git(["switch", "main"], ctx.cwd);
				await git(["pull", "--ff-only", "origin", "main"], ctx.cwd);
				await git(["branch", "-d", branch], ctx.cwd);

				return toolResult(`PR #${pr.number} merged successfully. Deleted ${branch} and returned to up-to-date main.`, {
					status: "merged",
					branch,
					pr,
				});
			} catch (error) {
				const reason = error instanceof Error ? error.message : String(error);
				return toolResult(`Merge workflow failed: ${reason}`, { status: "failed", branch, pr, reason }, true);
			}
		},
	});
}
