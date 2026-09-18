/**
 * Remote control extension
 *
 * `/rc` explicitly starts a Telegram bridge inside this Pi process. It stops with
 * `/rc stop`, `/rc logout`, or Pi shutdown; there is no background daemon.
 * Inside a Git repository, the current conversation is exposed in a session topic.
 */

import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { RemoteControlCoordinator, RemoteControlError, type LivePiSession } from "./coordinator.ts";
import { JsonAgentSessionStore, JsonCredentialStore, JsonRepositoryRegistry, JsonStateStore } from "./state.ts";
import { createTelegramBotApi } from "./telegram.ts";

const execFileAsync = promisify(execFile);

const STATUS_KEY = "rc";
const SUBCOMMANDS = [
	{ value: "start", description: "Start remote control (default)" },
	{ value: "stop", description: "Stop accepting Telegram messages" },
	{ value: "status", description: "Show login and bridge state" },
	{ value: "login", description: "Link a BotFather token, owner, and forum group" },
	{ value: "logout", description: "Stop remote control and remove local credentials" },
];

// Machine-local on purpose: never under ~/.pi/agent, which is partly symlinked from dotfiles.
const configDir = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "pi-remote-control");
const stateDir = join(process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "pi-remote-control");

function unavailable(feature: string): never {
	throw new Error(`${feature} is not available in remote control yet.`);
}

function createCoordinator(): RemoteControlCoordinator {
	const state = new JsonStateStore(join(stateDir, "state.json"));
	return new RemoteControlCoordinator({
		repositories: new JsonRepositoryRegistry(state),
		sessions: new JsonAgentSessionStore(state),
		workspaces: { create: () => unavailable("Workspace creation"), adopt: () => unavailable("Workspace adoption") },
		pi: { create: () => unavailable("Agent session creation") },
		telegram: { createSessionTopic: () => unavailable("Session topic creation") },
		credentials: new JsonCredentialStore(join(configDir, "credentials.json")),
		telegramBot: (token) => createTelegramBotApi(token),
	});
}

function describe(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

async function git(cwd: string, args: string[]): Promise<string> {
	const result = await execFileAsync("git", ["-C", cwd, ...args], { encoding: "utf8" });
	return result.stdout.trim();
}

/** The worktree, branch, and main repository `cwd` belongs to, or undefined outside Git. */
async function gitWorkspace(cwd: string): Promise<{ workspace: string; branch: string; repositoryPath: string } | undefined> {
	let workspace: string;
	try {
		workspace = await git(cwd, ["rev-parse", "--show-toplevel"]);
	} catch {
		return undefined;
	}
	const commonDir = await git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
	const branch = await git(cwd, ["branch", "--show-current"])
		|| `detached@${await git(cwd, ["rev-parse", "--short", "HEAD"]).catch(() => "unborn")}`;
	return { workspace, branch, repositoryPath: basename(commonDir) === ".git" ? dirname(commonDir) : commonDir };
}

type TextBlock = { type: string; text?: string };
type RunMessage = { role: string; content?: string | TextBlock[]; stopReason?: string; errorMessage?: string };

/** The final assistant message of a run, as the session topic's response. */
function runResponse(messages: RunMessage[]): { text: string; error?: string; aborted?: boolean } | undefined {
	const last = messages.findLast((message) => message.role === "assistant");
	if (!last) return undefined;
	const text = typeof last.content === "string"
		? last.content
		: (last.content ?? []).filter((block) => block.type === "text").map((block) => block.text ?? "").join("\n");
	if (last.stopReason === "aborted") return { text, aborted: true };
	if (last.stopReason === "error") return { text, error: last.errorMessage || "unknown error" };
	return { text };
}

export default function remoteControlExtension(pi: ExtensionAPI): void {
	const coordinator = createCoordinator();

	async function login(ctx: ExtensionCommandContext): Promise<void> {
		if (!ctx.hasUI) {
			ctx.ui.notify("/rc login needs the interactive Pi UI.", "error");
			return;
		}
		const token = (await ctx.ui.input("Telegram bot token from @BotFather"))?.trim();
		if (!token) return;
		try {
			ctx.ui.setStatus(STATUS_KEY, "rc: waiting for Telegram login code");
			const credentials = await coordinator.login({
				token,
				onHandshakeCode: (code, bot) => {
					ctx.ui.notify(
						[
							"Finish linking remote control in Telegram (code expires in 5 minutes):",
							"1. Create a private group and enable Topics.",
							`2. Add @${bot.username} as an administrator with the Manage Topics right.`,
							`3. Send this message in the group: /rc_login ${code}`,
						].join("\n"),
						"info",
					);
				},
			});
			ctx.ui.notify(`Remote control linked to ${credentials.group.title ?? "the forum group"}. Run /rc to start.`, "info");
		} catch (error) {
			ctx.ui.notify(`Remote control login failed: ${describe(error)}`, "error");
		} finally {
			ctx.ui.setStatus(STATUS_KEY, undefined);
		}
	}

	/** The current conversation as remote control drives it. Telegram prompts use Pi's queueing, so a run starting meanwhile is steered, not rejected. */
	async function liveSession(ctx: ExtensionCommandContext): Promise<LivePiSession | undefined> {
		const git = await gitWorkspace(ctx.cwd);
		if (!git) return undefined;
		return {
			id: ctx.sessionManager.getSessionId(),
			name: pi.getSessionName() ?? "",
			...git,
			isIdle: () => ctx.isIdle(),
			prompt: (text) => pi.sendUserMessage(text, { deliverAs: "steer" }),
			steer: (text) => pi.sendUserMessage(text, { deliverAs: "steer" }),
			followUp: (text) => pi.sendUserMessage(text, { deliverAs: "followUp" }),
		};
	}

	async function start(ctx: ExtensionCommandContext): Promise<void> {
		try {
			const session = await liveSession(ctx);
			const { alreadyRunning, credentials, session: exposed } = await coordinator.start({
				session,
				onMessage: async (message) => ctx.ui.notify(`Telegram: ${message.text}`, "info"),
				onError: (error) => ctx.ui.setStatus(STATUS_KEY, `rc: reconnecting (${describe(error)})`),
				onRecovered: () => ctx.ui.setStatus(STATUS_KEY, "rc: on"),
				onStopped: (reason) => {
					ctx.ui.setStatus(STATUS_KEY, undefined);
					ctx.ui.notify(`Remote control stopped: ${reason.message}`, "error");
				},
				onDeliveryError: (error) => ctx.ui.notify(`Remote control could not update Telegram: ${describe(error)}`, "warning"),
			});
			ctx.ui.setStatus(STATUS_KEY, "rc: on");
			const where = exposed ? ` This session is in topic "${exposed.topicName}".` : " Not in a Git repository, so this session is not exposed.";
			ctx.ui.notify(
				alreadyRunning ? "Remote control is already running." : `Remote control started in ${credentials.group.title ?? "Telegram"}.${where}`,
				"info",
			);
		} catch (error) {
			const hint = error instanceof RemoteControlError && error.code === "invalid-group" ? " Fix the group or run /rc login again." : "";
			ctx.ui.notify(`Remote control did not start: ${describe(error)}${hint}`, "error");
		}
	}

	async function status(ctx: ExtensionCommandContext): Promise<void> {
		const login = await coordinator.loginStatus();
		if (!login.loggedIn) {
			ctx.ui.notify("Remote control: not logged in. Run /rc login.", "info");
			return;
		}
		const bridge = coordinator.status();
		const topics = bridge.topics.length ? ` Session topics: ${bridge.topics.join(", ")}.` : "";
		ctx.ui.notify(`Remote control: ${bridge.running ? "running" : "stopped"}; bot ${login.bot ?? "unknown"} in ${login.group ?? "the forum group"}.${topics}`, "info");
	}

	pi.registerCommand("rc", {
		description: "Telegram remote control: start, stop, status, login, logout",
		getArgumentCompletions: (prefix) => {
			const items = SUBCOMMANDS.filter((item) => item.value.startsWith(prefix.trim()))
				.map((item) => ({ value: item.value, label: item.value, description: item.description }));
			return items.length ? items : null;
		},
		handler: async (args, ctx) => {
			const subcommand = args.trim().split(/\s+/)[0] || "start";
			try {
				await run(subcommand, ctx);
			} catch (error) {
				ctx.ui.notify(`/rc ${subcommand} failed: ${describe(error)}`, "error");
			}
		},
	});

	async function run(subcommand: string, ctx: ExtensionCommandContext): Promise<void> {
		switch (subcommand) {
			case "start":
				return start(ctx);
			case "stop": {
				const wasRunning = await coordinator.stop();
				ctx.ui.setStatus(STATUS_KEY, undefined);
				ctx.ui.notify(wasRunning ? "Remote control stopped." : "Remote control was not running.", "info");
				return;
			}
			case "status":
				return status(ctx);
			case "login":
				return login(ctx);
			case "logout": {
				const { hadCredentials } = await coordinator.logout();
				ctx.ui.setStatus(STATUS_KEY, undefined);
				ctx.ui.notify(
					hadCredentials
						? "Remote control stopped and local credentials removed. Revoke the token in @BotFather to disable the bot entirely."
						: "Remote control was not logged in.",
					"info",
				);
				return;
			}
			default:
				ctx.ui.notify(`Unknown /rc command: ${subcommand}. Use ${SUBCOMMANDS.map((item) => item.value).join(", ")}.`, "error");
		}
	}

	// Mirror this conversation's work into its session topic. The coordinator ignores
	// these while the bridge is stopped. Tool output is never forwarded.
	let pendingPrompt: string | undefined;
	pi.on("before_agent_start", async (event) => {
		pendingPrompt = event.prompt;
	});
	pi.on("agent_start", async (_event, ctx) => {
		coordinator.recordActivity(ctx.sessionManager.getSessionId(), { type: "run-start", prompt: pendingPrompt });
		pendingPrompt = undefined;
	});
	pi.on("tool_execution_start", async (event, ctx) => {
		coordinator.recordActivity(ctx.sessionManager.getSessionId(), { type: "tool-start", toolCallId: event.toolCallId, toolName: event.toolName, args: event.args });
	});
	pi.on("tool_execution_end", async (event, ctx) => {
		coordinator.recordActivity(ctx.sessionManager.getSessionId(), { type: "tool-end", toolCallId: event.toolCallId, isError: event.isError });
	});
	pi.on("agent_end", async (event, ctx) => {
		const response = runResponse(event.messages as RunMessage[]);
		if (response) coordinator.recordActivity(ctx.sessionManager.getSessionId(), { type: "response", ...response });
	});
	pi.on("agent_settled", async (_event, ctx) => {
		coordinator.recordActivity(ctx.sessionManager.getSessionId(), { type: "settled" });
	});

	// Pi tears down this extension instance on quit, reload, and session switches;
	// the bridge must never outlive it. This also cancels a pending login.
	pi.on("session_shutdown", async () => {
		await coordinator.stop();
	});
}
