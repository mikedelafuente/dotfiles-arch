/**
 * Remote control extension
 *
 * `/rc` explicitly starts a Telegram bridge inside this Pi process. It stops with
 * `/rc stop`, `/rc logout`, or Pi shutdown; there is no background daemon.
 */

import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { RemoteControlCoordinator, RemoteControlError } from "./coordinator.ts";
import { JsonAgentSessionStore, JsonCredentialStore, JsonRepositoryRegistry, JsonStateStore } from "./state.ts";
import { createTelegramBotApi } from "./telegram.ts";

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

	async function start(ctx: ExtensionCommandContext): Promise<void> {
		try {
			const { alreadyRunning, credentials } = await coordinator.start({
				onMessage: async (message) => ctx.ui.notify(`Telegram: ${message.text}`, "info"),
				onError: (error) => ctx.ui.setStatus(STATUS_KEY, `rc: reconnecting (${describe(error)})`),
			});
			ctx.ui.setStatus(STATUS_KEY, "rc: on");
			ctx.ui.notify(alreadyRunning ? "Remote control is already running." : `Remote control started in ${credentials.group.title ?? "Telegram"}.`, "info");
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
		const bridge = coordinator.status().running ? "running" : "stopped";
		ctx.ui.notify(`Remote control: ${bridge}; bot ${login.bot ?? "unknown"} in ${login.group ?? "the forum group"}.`, "info");
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
		},
	});

	// Pi tears down this extension instance on quit, reload, and session switches;
	// the bridge must never outlive it.
	pi.on("session_shutdown", async () => {
		await coordinator.stop();
	});
}
