/**
 * Remote control extension
 *
 * `/rc` explicitly starts a Telegram bridge inside this Pi process. It stops with
 * `/rc stop`, `/rc logout`, or Pi shutdown; there is no background daemon.
 * Inside a Git repository, the current conversation is exposed in a session topic.
 * Agent sessions `/rc new` or `/rc attach` start run as `pi --mode rpc` children.
 * While a conversation is remote-controlled, merges, branch deletions, deployments,
 * and privileged commands wait for the owner's approval.
 */

import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { RemoteControlCoordinator, RemoteControlError, type LivePiSession, type PiActivity, type PiCommand } from "./coordinator.ts";
import { GitWorkspaces, gitWorkspace } from "./git-workspaces.ts";
import { SessionLeaseFiles } from "./leases.ts";
import { errorMessage, renderSessions, runResponse, type RunMessage } from "./messages.ts";
import { PiDelivery } from "./pi-delivery.ts";
import { AGENT_ENV, COMMANDS_CHANGED_STATUS, RpcPiSessions } from "./pi-rpc.ts";
import { sensitiveOperation, type SensitiveOperation } from "./sensitive.ts";
import { JsonAgentSessionStore, JsonCredentialStore, JsonRepositoryRegistry, JsonStateStore } from "./state.ts";
import { createTelegramBotApi } from "./telegram.ts";

const STATUS_KEY = "rc";
const SUBCOMMANDS = [
	{ value: "start", description: "Start remote control (default)" },
	{ value: "stop", description: "Stop accepting Telegram messages" },
	{ value: "status", description: "Show login and bridge state" },
	{ value: "new", description: "new <name>: adopt this branch/worktree, or start an agent in a new worktree" },
	{ value: "sessions", description: "List agent sessions by repository" },
	{ value: "attach", description: "attach <session>: reconnect a disconnected agent session" },
	{ value: "login", description: "Link a BotFather token, owner, and forum group" },
	{ value: "logout", description: "Stop remote control and remove local credentials" },
];

/** This Pi is an agent session remote control started: every sensitive operation needs the owner's approval. */
const isAgent = process.env[AGENT_ENV] === "1";

type ThinkingLevel = Parameters<ExtensionAPI["setThinkingLevel"]>[0];

// Machine-local on purpose: never under ~/.pi/agent, which is partly symlinked from dotfiles.
const configDir = join(process.env.XDG_CONFIG_HOME || join(homedir(), ".config"), "pi-remote-control");
const stateDir = join(process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "pi-remote-control");

/** Agents run the same Pi as this process: its runtime and its entry script. */
function piCommand(): string[] {
	return process.argv[1] ? [process.execPath, process.argv[1]] : ["pi"];
}

function createCoordinator(leases: SessionLeaseFiles): RemoteControlCoordinator {
	const state = new JsonStateStore(join(stateDir, "state.json"));
	return new RemoteControlCoordinator({
		repositories: new JsonRepositoryRegistry(state),
		sessions: new JsonAgentSessionStore(state),
		workspaces: new GitWorkspaces(),
		pi: new RpcPiSessions({ command: piCommand() }),
		leases,
		credentials: new JsonCredentialStore(join(configDir, "credentials.json")),
		telegramBot: (token) => createTelegramBotApi(token),
	});
}

export default function remoteControlExtension(pi: ExtensionAPI): void {
	const leases = new SessionLeaseFiles(join(stateDir, "leases"));
	const coordinator = createCoordinator(leases);

	// Every Pi running this extension leases its conversation, whether or not it runs /rc,
	// so /rc attach never resumes a conversation another Pi is writing.
	let leased: string | undefined;
	pi.on("session_start", async (event, ctx) => {
		leased = ctx.sessionManager.getSessionId();
		await leases.acquire(leased).catch((error) => ctx.ui.notify(`Remote control could not record this session's lease: ${errorMessage(error)}`, "warning"));
		// Tells the Pi that started this agent to read its commands again (see pi-rpc.ts).
		if (isAgent && event.reason === "reload") ctx.ui.setStatus(COMMANDS_CHANGED_STATUS, new Date().toISOString());
	});

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
			ctx.ui.notify(`Remote control login failed: ${errorMessage(error)}`, "error");
		} finally {
			ctx.ui.setStatus(STATUS_KEY, undefined);
		}
	}

	// Holds Telegram messages while a prompt is starting or Pi is compacting.
	let delivery: PiDelivery | undefined;

	/** What Pi discovered now, so a reload is always reflected. */
	const discovered = (): PiCommand[] => pi.getCommands().map(({ name, description, source }) => ({ name, description, source }));

	/** A prompt template or skill command, which Pi expands; extension commands are never run from Telegram. */
	function expandable(text: string): boolean {
		const name = /^\/(\S+)/.exec(text.trim())?.[1];
		return name !== undefined && discovered().some((command) => command.name === name && command.source !== "extension");
	}

	async function runBuiltin(ctx: ExtensionContext, name: string, args: string): Promise<string> {
		switch (name) {
			case "compact":
				return new Promise((resolve, reject) => {
					ctx.compact({
						customInstructions: args || undefined,
						onComplete: (result) => resolve(`Compacted the context from ${result.tokensBefore} to about ${result.estimatedTokensAfter ?? "?"} tokens.`),
						onError: reject,
					});
				});
			case "thinking":
				pi.setThinkingLevel(args as ThinkingLevel);
				return `Thinking level set to ${pi.getThinkingLevel()}.`;
			default:
				throw new Error(`/${name} is not a Pi built-in remote control can run.`);
		}
	}

	/** The current conversation as remote control drives it, with the branch it is on now. */
	async function liveSession(ctx: ExtensionCommandContext): Promise<LivePiSession | undefined> {
		const workspace = await gitWorkspace(ctx.cwd);
		if (!workspace) return undefined;
		// One delivery queue per conversation: its route may be rebuilt, but held messages must not be lost.
		const current = delivery ??= new PiDelivery({
			send: (text, deliverAs) => pi.sendUserMessage(text, { deliverAs, expandPromptTemplates: expandable(text) }),
			isIdle: () => ctx.isIdle(),
		});
		return {
			id: ctx.sessionManager.getSessionId(),
			name: pi.getSessionName() ?? "",
			sessionFile: ctx.sessionManager.getSessionFile(),
			...workspace,
			isIdle: () => ctx.isIdle() && current.isReady(),
			prompt: (text) => current.prompt(text),
			steer: (text) => current.steer(text),
			followUp: (text) => current.followUp(text),
			rename: (name) => pi.setSessionName(name),
			commands: async () => discovered(),
			abort: async () => ctx.abort(),
			runBuiltin: (name, args) => runBuiltin(ctx, name, args),
		};
	}

	async function newSession(name: string, ctx: ExtensionCommandContext): Promise<void> {
		if (!name) {
			ctx.ui.notify("Usage: /rc new <name>", "error");
			return;
		}
		const current = await liveSession(ctx);
		if (!current) {
			ctx.ui.notify("Run /rc new inside a Git repository.", "error");
			return;
		}
		ctx.ui.notify(`Starting agent session "${name}"…`, "info");
		const { session, adopted } = await coordinator.newSession({ name, current });
		ctx.ui.notify(
			adopted
				? `This conversation is now agent session "${session.name}" on ${session.branch}, in topic "${session.topicName}".`
				: `Started agent session "${session.name}" on ${session.branch} in ${session.workspace}, in topic "${session.topicName}".`,
			"info",
		);
	}

	async function attach(reference: string, ctx: ExtensionCommandContext): Promise<void> {
		if (!reference) {
			ctx.ui.notify("Usage: /rc attach <session>", "error");
			return;
		}
		const { session, alreadyConnected } = await coordinator.attach(reference);
		ctx.ui.notify(
			alreadyConnected ? `"${session.name}" is already connected in topic "${session.topicName}".` : `Reconnected "${session.name}" in topic "${session.topicName}".`,
			"info",
		);
	}

	async function start(ctx: ExtensionCommandContext): Promise<void> {
		try {
			const session = await liveSession(ctx);
			const { alreadyRunning, credentials, session: exposed } = await coordinator.start({
				session,
				onMessage: async (message) => ctx.ui.notify(`Telegram: ${message.text}`, "info"),
				onError: (error) => ctx.ui.setStatus(STATUS_KEY, `rc: reconnecting (${errorMessage(error)})`),
				onRecovered: () => ctx.ui.setStatus(STATUS_KEY, "rc: on"),
				onStopped: (reason) => {
					ctx.ui.setStatus(STATUS_KEY, undefined);
					ctx.ui.notify(`Remote control stopped: ${reason.message}`, "error");
				},
				onDeliveryError: (error) => ctx.ui.notify(`Remote control could not update Telegram: ${errorMessage(error)}`, "warning"),
			});
			ctx.ui.setStatus(STATUS_KEY, "rc: on");
			const where = exposed ? ` This session is in topic "${exposed.topicName}".` : " Not in a Git repository, so this session is not exposed.";
			ctx.ui.notify(
				alreadyRunning ? "Remote control is already running." : `Remote control started in ${credentials.group.title ?? "Telegram"}.${where}`,
				"info",
			);
		} catch (error) {
			const hint = error instanceof RemoteControlError && error.code === "invalid-group" ? " Fix the group or run /rc login again." : "";
			ctx.ui.notify(`Remote control did not start: ${errorMessage(error)}${hint}`, "error");
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
		description: "Telegram remote control: start, stop, status, new, sessions, attach, login, logout",
		getArgumentCompletions: (prefix) => {
			const items = SUBCOMMANDS.filter((item) => item.value.startsWith(prefix.trim()))
				.map((item) => ({ value: item.value, label: item.value, description: item.description }));
			return items.length ? items : null;
		},
		handler: async (args, ctx) => {
			const [, subcommand = "start", rest = ""] = /^(\S*)\s*([\s\S]*)$/.exec(args.trim()) ?? [];
			try {
				await run(subcommand || "start", rest.trim(), ctx);
			} catch (error) {
				ctx.ui.notify(`/rc ${subcommand} failed: ${errorMessage(error)}`, "error");
			}
		},
	});

	async function run(subcommand: string, rest: string, ctx: ExtensionCommandContext): Promise<void> {
		switch (subcommand) {
			case "start":
				return start(ctx);
			case "new":
				return newSession(rest, ctx);
			case "sessions":
				ctx.ui.notify(renderSessions(await coordinator.sessions()), "info");
				return;
			case "attach":
				return attach(rest, ctx);
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

	/**
	 * Asks for approval both here and in Telegram; the first answer wins and
	 * withdraws the other question.
	 */
	async function approveHereOrRemotely(ctx: ExtensionContext, operation: SensitiveOperation): Promise<boolean> {
		const withdraw = new AbortController();
		const remote = coordinator.requestApproval(ctx.sessionManager.getSessionId(), { title: operation.title, message: operation.detail }, withdraw.signal);
		const local = ctx.hasUI
			? ctx.ui.confirm(operation.title, `${operation.detail}\n\nAlso asked in Telegram.`, { signal: withdraw.signal })
			: new Promise<boolean>(() => undefined);
		try {
			return await Promise.race([remote, local]);
		} finally {
			withdraw.abort();
		}
	}

	// A remote-controlled conversation runs sensitive operations only once the owner approves them.
	pi.on("tool_call", async (event, ctx) => {
		const operation = sensitiveOperation(event.toolName, event.input);
		if (!operation) return;
		let approved: boolean;
		if (isAgent) approved = await ctx.ui.confirm(operation.title, operation.detail); // Answered in the agent's session topic.
		else if (coordinator.isRemoteControlled(ctx.sessionManager.getSessionId())) approved = await approveHereOrRemotely(ctx, operation);
		else return;
		if (approved) return;
		return { block: true, reason: `The owner did not approve this ${operation.kind.replace("-", " ")}: ${operation.detail}. Do not retry it; ask the owner instead.` };
	});

	// Mirror this conversation's work into its session topic. The coordinator ignores
	// these while the bridge is stopped. Tool output is never forwarded.
	const report = (ctx: ExtensionContext, activity: PiActivity) => coordinator.recordActivity(ctx.sessionManager.getSessionId(), activity);
	let pendingPrompt: string | undefined;
	pi.on("before_agent_start", async (event) => {
		pendingPrompt = event.prompt;
	});
	pi.on("agent_start", async (_event, ctx) => {
		delivery?.runStarted();
		report(ctx, { type: "run-start", prompt: pendingPrompt });
		pendingPrompt = undefined;
	});
	pi.on("tool_execution_start", async (event, ctx) => {
		report(ctx, { type: "tool-start", toolCallId: event.toolCallId, toolName: event.toolName, args: event.args });
	});
	pi.on("tool_execution_end", async (event, ctx) => {
		report(ctx, { type: "tool-end", toolCallId: event.toolCallId, isError: event.isError });
	});
	pi.on("agent_end", async (event, ctx) => {
		const response = runResponse(event.messages as RunMessage[]);
		if (response) report(ctx, { type: "response", ...response });
	});
	pi.on("agent_settled", async (_event, ctx) => {
		report(ctx, { type: "settled" });
	});
	pi.on("session_before_compact", async () => {
		delivery?.compactionStarted();
	});
	pi.on("session_compact", async () => {
		delivery?.compactionEnded();
	});
	pi.on("session_compact_failed", async () => {
		delivery?.compactionEnded();
	});

	// Pi tears down this extension instance on quit, reload, and session switches;
	// neither the bridge nor the agent processes may outlive it. This also cancels a pending login.
	pi.on("session_shutdown", async () => {
		await coordinator.shutdown();
		delivery?.dispose();
		if (leased) await leases.release(leased).catch(() => undefined);
	});
}
