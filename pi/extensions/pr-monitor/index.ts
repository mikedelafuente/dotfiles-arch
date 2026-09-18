/**
 * PR Monitor extension
 *
 * Adds a tool that watches a GitHub pull request until it is merged or a
 * terminal failure is detected.
 */

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Static, Type } from "typebox";

const execFileAsync = promisify(execFile);

const monitorPrSchema = Type.Object({
	pr: Type.String({ description: "Pull request number or URL" }),
	repo: Type.Optional(Type.String({ description: "GitHub repository (OWNER/REPO); defaults to the current repository" })),
	pollIntervalSeconds: Type.Optional(
		Type.Integer({ description: "Seconds between checks (default: 10)", minimum: 10, default: 10 }),
	),
	timeoutMinutes: Type.Optional(
		Type.Integer({ description: "Maximum monitoring time in minutes (default: 30)", minimum: 1, default: 30 }),
	),
});

export type MonitorPrInput = Static<typeof monitorPrSchema>;

export type PullRequest = {
	number: number;
	title: string;
	state: "OPEN" | "CLOSED";
	isDraft: boolean;
	mergeStateStatus: string;
	mergedAt: string | null;
	url: string;
	headRefName: string;
	baseRefName: string;
};

export type Check = {
	name: string;
	state: string;
	bucket: string;
	link?: string;
};

type MonitorDetails = {
	status: "monitoring" | "merged" | "failed" | "timed_out" | "cancelled";
	pr?: PullRequest;
	checks?: Check[];
	polls: number;
	elapsedSeconds: number;
	reason?: string;
};

type CommandError = Error & { stdout?: string; stderr?: string };

async function ghJson<T>(args: string[], signal: AbortSignal | undefined, cwd = process.cwd()): Promise<T> {
	const result = await execFileAsync("gh", args, { cwd, encoding: "utf8", signal });
	return JSON.parse(result.stdout) as T;
}

export async function getPullRequestChecks(
	pr: string,
	repo: string | undefined,
	signal: AbortSignal | undefined,
	cwd = process.cwd(),
): Promise<Check[]> {
	const repoArgs = repo ? ["--repo", repo] : [];
	try {
		return await ghJson<Check[]>(["pr", "checks", pr, ...repoArgs, "--json", "name,state,bucket,link"], signal, cwd);
	} catch (error) {
		const commandError = error as CommandError;
		if (!commandError.stdout?.trim()) throw error;
		return JSON.parse(commandError.stdout) as Check[];
	}
}

export async function getPullRequest(
	pr: string,
	repo: string | undefined,
	signal: AbortSignal | undefined,
	cwd = process.cwd(),
): Promise<PullRequest> {
	const repoArgs = repo ? ["--repo", repo] : [];
	return ghJson<PullRequest>(
		["pr", "view", pr, ...repoArgs, "--json", "number,title,state,isDraft,mergeStateStatus,mergedAt,url,headRefName,baseRefName"],
		signal,
		cwd,
	);
}

export function failedCheck(check: Check): boolean {
	return ["fail", "failure", "error", "cancelled", "timed_out"].includes(
		(check.bucket || check.state).toLowerCase(),
	);
}

export function pendingCheck(check: Check): boolean {
	return ["pending", "queued", "in_progress", "expected"].includes(
		(check.bucket || check.state).toLowerCase(),
	);
}

export function formatChecks(checks: Check[]): string {
	if (checks.length === 0) return "no checks reported";
	const failed = checks.filter(failedCheck).length;
	const pending = checks.filter(pendingCheck).length;
	const passed = checks.length - failed - pending;
	return `${passed} passed, ${pending} pending, ${failed} failed`;
}

function sleep(ms: number, signal: AbortSignal | undefined): Promise<void> {
	return new Promise((resolve, reject) => {
		const timer = setTimeout(resolve, ms);
		if (!signal) return;
		if (signal.aborted) {
			clearTimeout(timer);
			reject(new Error("Monitoring cancelled"));
			return;
		}
		signal.addEventListener(
			"abort",
			() => {
				clearTimeout(timer);
				reject(new Error("Monitoring cancelled"));
			},
			{ once: true },
		);
	});
}

function result(text: string, details: MonitorDetails, isError = false) {
	return {
		content: [{ type: "text" as const, text }],
		details,
		...(isError ? { isError: true } : {}),
	};
}

export default function prMonitorExtension(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "monitor_pr",
		label: "Monitor PR",
		description: "Monitor a GitHub pull request until it is merged or a failure is detected.",
		promptSnippet: "Monitor a pull request until merged or failed",
		promptGuidelines: [
			"Use monitor_pr after creating or requesting a PR merge when the user wants its outcome monitored.",
			"Do not use it for general PR status checks when no waiting is requested.",
		],
		parameters: monitorPrSchema,
		executionMode: "sequential",

		async execute(_toolCallId, params: MonitorPrInput, signal, onUpdate) {
			const intervalSeconds = params.pollIntervalSeconds ?? 10;
			const timeoutMinutes = params.timeoutMinutes ?? 30;
			const startedAt = Date.now();
			let polls = 0;

			const emit = (text: string, details: MonitorDetails) => {
				onUpdate?.(result(text, details));
			};

			try {
				while (true) {
					polls++;
					const pr = await getPullRequest(params.pr, params.repo, signal);
					const checks = await getPullRequestChecks(params.pr, params.repo, signal);
					const elapsedSeconds = Math.round((Date.now() - startedAt) / 1000);
					const baseDetails = { pr, checks, polls, elapsedSeconds };

					if (pr.mergedAt || pr.state === "CLOSED" && pr.mergedAt) {
						return result(`PR #${pr.number} merged: ${pr.title}\n${pr.url}`, {
							...baseDetails,
							status: "merged",
						});
					}

					const failed = checks.find(failedCheck);
					if (failed) {
						const reason = `Check failed: ${failed.name} (${failed.state || failed.bucket})`;
						return result(`PR #${pr.number} failed — ${reason}\n${pr.url}`, {
							...baseDetails,
							status: "failed",
							reason,
						}, true);
					}

					if (pr.state === "CLOSED") {
						const reason = "The pull request was closed without being merged";
						return result(`PR #${pr.number} failed — ${reason}\n${pr.url}`, {
							...baseDetails,
							status: "failed",
							reason,
						}, true);
					}

					if (pr.mergeStateStatus === "DIRTY") {
						const reason = "The pull request has merge conflicts";
						return result(`PR #${pr.number} failed — ${reason}\n${pr.url}`, {
							...baseDetails,
							status: "failed",
							reason,
						}, true);
					}

					if (elapsedSeconds >= timeoutMinutes * 60) {
						const reason = `Monitoring timed out after ${timeoutMinutes} minutes`;
						return result(`PR #${pr.number} timed out — ${formatChecks(checks)}\n${pr.url}`, {
							...baseDetails,
							status: "timed_out",
							reason,
						}, true);
					}

					emit(
						`Monitoring PR #${pr.number}: ${pr.title}\n${pr.state.toLowerCase()}, ${pr.mergeStateStatus.toLowerCase()}; ${formatChecks(checks)}. Next check in ${intervalSeconds}s.`,
						{ ...baseDetails, status: "monitoring" },
					);
					await sleep(intervalSeconds * 1000, signal);
				}
			} catch (error) {
				if (signal?.aborted) {
					return result("PR monitoring cancelled.", {
						status: "cancelled",
						polls,
						elapsedSeconds: Math.round((Date.now() - startedAt) / 1000),
					}, true);
				}
				const message = error instanceof Error ? error.message : String(error);
				return result(`Could not monitor PR ${params.pr}: ${message}`, {
					status: "failed",
					polls,
					elapsedSeconds: Math.round((Date.now() - startedAt) / 1000),
					reason: message,
				}, true);
			}
		},
	});
}
