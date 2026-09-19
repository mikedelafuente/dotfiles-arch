/**
 * Agent sessions as `pi --mode rpc` child processes, one per workspace.
 *
 * Each process runs a complete Pi (extensions, skills, and session persistence) in
 * its own worktree, so an agent's tools can never reach another agent's files. A
 * child exits when its stdin closes, so it cannot outlive the Pi that started it.
 */
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { access } from "node:fs/promises";
import type { AgentProcess, AgentSession, PiCommand, PiDialog, PiSessionAdapter, PiSessionEvents, Repository, Workspace } from "./coordinator.ts";
import { runResponse, type RunMessage } from "./messages.ts";

export type RpcPiSessionsOptions = {
	/** How to run Pi, e.g. `[process.execPath, "/path/to/pi/cli.js"]`; `--mode rpc` and session flags are appended. */
	command: string[];
	env?: Record<string, string>;
	startTimeoutMs?: number;
};

const DEFAULT_START_TIMEOUT_MS = 30_000;
/** How long a prompt may take to start a run before the session counts as idle again. */
const RUN_START_TIMEOUT_MS = 30_000;
const CLOSE_TIMEOUT_MS = 3000;
const STDERR_LIMIT = 4000;
const DIALOG_METHODS = new Set(["select", "confirm", "input", "editor"]);

/** Set in the environment of every agent Pi remote control starts, so this extension knows it is remote-controlled there. */
export const AGENT_ENV = "PI_REMOTE_CONTROL_AGENT";
/** The status key an agent's Pi sets after reloading its resources, so its discovered commands are read again. */
export const COMMANDS_CHANGED_STATUS = "remote-control:commands";

type RpcResponse = { id?: string; type: "response"; command: string; success: boolean; data?: unknown; error?: string };
type RpcEvent = { type: string; [key: string]: unknown };
type Location = { name: string; workspace: string; branch: string; repositoryPath: string };

function lastLine(text: string): string {
	return text.trim().split("\n").at(-1) ?? "";
}

class RpcAgent implements AgentProcess {
	id = "";
	sessionFile?: string;
	name: string;
	readonly workspace: string;
	readonly branch: string;
	readonly repositoryPath: string;

	private readonly child: ChildProcessWithoutNullStreams;
	private readonly events: PiSessionEvents;
	private readonly pending = new Map<string, { resolve(response: RpcResponse): void; reject(error: Error): void }>();
	private readonly exited: Promise<void>;
	/** What Pi discovered, as of the last `get_commands`. */
	private commandList: PiCommand[] = [];
	/** Settles once the latest `get_commands` answered; messages wait for it, so a reload is honoured. */
	private commandsReady: Promise<void> = Promise.resolve();
	private nextId = 1;
	private stderr = "";
	private closing = false;
	/** A start failure is reported by `start()`, not as an exit. */
	private started = false;
	private running = false;
	/** Runs from sending a prompt while idle until Pi reports the run started. */
	private runStartTimer?: ReturnType<typeof setTimeout>;
	private runPrompt?: string;

	constructor(options: RpcPiSessionsOptions, cwd: string, args: string[], location: Location, events: PiSessionEvents) {
		this.name = location.name;
		this.workspace = location.workspace;
		this.branch = location.branch;
		this.repositoryPath = location.repositoryPath;
		this.events = events;
		const [command, ...prefix] = options.command;
		this.child = spawn(command, [...prefix, "--mode", "rpc", ...args], { cwd, env: { ...process.env, ...options.env, [AGENT_ENV]: "1" }, stdio: ["pipe", "pipe", "pipe"] });
		this.child.stderr.setEncoding("utf8").on("data", (chunk: string) => { this.stderr = (this.stderr + chunk).slice(-STDERR_LIMIT); });
		this.child.stdin.on("error", () => undefined);
		let buffer = "";
		// Strict JSONL: split on LF only, as RPC mode requires.
		this.child.stdout.setEncoding("utf8").on("data", (chunk: string) => {
			buffer += chunk;
			for (let index = buffer.indexOf("\n"); index !== -1; index = buffer.indexOf("\n")) {
				const line = buffer.slice(0, index).replace(/\r$/, "");
				buffer = buffer.slice(index + 1);
				if (line.trim()) this.handleLine(line);
			}
		});
		this.exited = new Promise((resolve) => {
			const finish = (reason: string) => {
				clearTimeout(this.runStartTimer);
				const error = this.failure(reason);
				for (const request of this.pending.values()) request.reject(error);
				this.pending.clear();
				if (this.started && !this.closing) events.exited(error.message.replace(/^Pi /, ""));
				resolve();
			};
			this.child.once("error", (error) => finish(`could not start (${error.message})`));
			this.child.once("exit", (code, signal) => finish(signal ? `was killed (${signal})` : `exited (exit code ${code})`));
		});
	}

	async start(timeoutMs: number): Promise<void> {
		const timeout = setTimeout(() => this.child.kill("SIGKILL"), timeoutMs);
		try {
			const state = (await this.request({ type: "get_state" })).data as { sessionId: string; sessionFile?: string };
			this.id = state.sessionId;
			this.sessionFile = state.sessionFile;
			this.started = true;
		} catch (error) {
			this.closing = true;
			this.child.kill("SIGKILL");
			throw error;
		} finally {
			clearTimeout(timeout);
		}
		await this.refreshCommands();
	}

	async commands(): Promise<PiCommand[]> {
		await this.refreshCommands();
		return this.commandList.map((command) => ({ ...command }));
	}

	/** Reads Pi's discovered commands again; on failure, the previous list stays. */
	private refreshCommands(): Promise<void> {
		this.commandsReady = this.request({ type: "get_commands" }).then(
			(response) => {
				const commands = (response.data as { commands?: PiCommand[] }).commands ?? [];
				this.commandList = commands.map(({ name, description, source }) => ({ name, description, source }));
			},
			() => undefined,
		);
		return this.commandsReady;
	}

	async abort(): Promise<void> {
		await this.request({ type: "abort" });
	}

	async runBuiltin(name: string, args: string): Promise<string> {
		switch (name) {
			case "compact": {
				const response = await this.request({ type: "compact", ...(args ? { customInstructions: args } : {}) });
				const { tokensBefore, estimatedTokensAfter } = (response.data ?? {}) as { tokensBefore?: number; estimatedTokensAfter?: number };
				return tokensBefore === undefined ? "Compacted the context." : `Compacted the context from ${tokensBefore} to about ${estimatedTokensAfter} tokens.`;
			}
			case "thinking":
				await this.request({ type: "set_thinking_level", level: args });
				return `Thinking level set to ${args}.`;
			default:
				throw new Error(`/${name} is not a Pi built-in remote control can run.`);
		}
	}

	isIdle(): boolean {
		return !this.running && !this.runStartTimer;
	}

	prompt(text: string): void {
		if (this.isIdle()) {
			this.runPrompt = text;
			this.runStartTimer = setTimeout(() => { this.runStartTimer = undefined; }, RUN_START_TIMEOUT_MS);
			this.runStartTimer.unref?.();
		}
		// From idle, Pi starts a run and ignores the mode; one that just started is steered.
		this.send(text, "steer");
	}

	steer(text: string): void {
		this.send(text, "steer");
	}

	followUp(text: string): void {
		this.send(text, "followUp");
	}

	private isRunning(): boolean {
		return this.child.exitCode === null && this.child.signalCode === null;
	}

	/** An error naming the last line Pi wrote to stderr, if any. */
	private failure(reason: string): Error {
		return new Error(`Pi ${reason}${this.stderr.trim() ? `: ${lastLine(this.stderr)}` : ""}`);
	}

	async close(): Promise<void> {
		this.closing = true;
		if (this.isRunning()) {
			this.child.stdin.end();
			const terminate = setTimeout(() => this.child.kill("SIGTERM"), CLOSE_TIMEOUT_MS);
			const kill = setTimeout(() => this.child.kill("SIGKILL"), CLOSE_TIMEOUT_MS * 2);
			await this.exited;
			clearTimeout(terminate);
			clearTimeout(kill);
		}
	}

	/**
	 * Uses RPC `prompt` for every message, so skills and prompt templates expand as
	 * they do locally. Extension commands are refused: they would run immediately,
	 * and remote approval of what they do does not exist yet.
	 */
	private send(text: string, streamingBehavior: "steer" | "followUp"): void {
		this.commandsReady.then(() => {
			const command = /^\/(\S+)/.exec(text.trim())?.[1];
			if (command && this.commandList.some((candidate) => candidate.source === "extension" && candidate.name === command)) {
				this.clearStarting();
				this.events.activity({ type: "notice", text: `/${command} is an extension command, which runs only in a local Pi: remote control cannot approve what it does.` });
				return;
			}
			this.request({ type: "prompt", message: text, streamingBehavior }).then(
				(response) => {
					if (response.success) return;
					this.clearStarting();
					this.events.activity({ type: "notice", text: `Pi did not accept the message: ${response.error ?? "unknown error"}` });
				},
				() => this.clearStarting(), // The process exited; `exited` reports it.
			);
		});
	}

	/** Answers a Pi dialog once the owner has; a dialog left unanswered would block Pi forever. */
	private answerDialog(id: unknown, answer: Promise<Record<string, unknown>>): void {
		answer
			.catch(() => ({ cancelled: true }))
			.then((fields) => {
				if (this.isRunning()) this.child.stdin.write(`${JSON.stringify({ type: "extension_ui_response", id, ...fields })}\n`);
			});
	}

	private clearStarting(): void {
		clearTimeout(this.runStartTimer);
		this.runStartTimer = undefined;
	}

	private request(command: Record<string, unknown>): Promise<RpcResponse> {
		const id = `rc-${this.nextId++}`;
		return new Promise((resolve, reject) => {
			if (!this.isRunning()) {
				reject(this.failure("exited"));
				return;
			}
			this.pending.set(id, { resolve, reject });
			this.child.stdin.write(`${JSON.stringify({ ...command, id })}\n`);
		});
	}

	private handleLine(line: string): void {
		let message: RpcResponse | RpcEvent;
		try {
			message = JSON.parse(line) as RpcResponse | RpcEvent;
		} catch {
			return;
		}
		if (message.type === "response") {
			const response = message as RpcResponse;
			const request = response.id === undefined ? undefined : this.pending.get(response.id);
			if (!request) return;
			this.pending.delete(response.id!);
			if (response.success || response.command === "prompt") request.resolve(response);
			else request.reject(new Error(`Pi ${response.command} failed: ${response.error ?? "unknown error"}`));
			return;
		}
		this.handleEvent(message as RpcEvent);
	}

	private handleEvent(event: RpcEvent): void {
		const report = this.events.activity;
		switch (event.type) {
			case "agent_start":
				this.clearStarting();
				this.running = true;
				report({ type: "run-start", prompt: this.runPrompt });
				this.runPrompt = undefined;
				return;
			case "tool_execution_start":
				report({ type: "tool-start", toolCallId: String(event.toolCallId), toolName: String(event.toolName), args: event.args });
				return;
			case "tool_execution_end":
				report({ type: "tool-end", toolCallId: String(event.toolCallId), isError: Boolean(event.isError) });
				return;
			case "agent_end": {
				const response = runResponse((event.messages ?? []) as RunMessage[]);
				if (response) report({ type: "response", ...response });
				return;
			}
			case "agent_settled":
				this.running = false;
				report({ type: "settled" });
				return;
			case "extension_ui_request": {
				const method = String(event.method);
				const dialog: PiDialog = {
					title: String(event.title ?? method),
					...(event.message ? { message: String(event.message) } : {}),
					...(typeof event.timeout === "number" ? { timeoutMs: event.timeout } : {}),
				};
				// Confirmations and selections go to the owner in the session topic.
				if (method === "confirm") {
					this.answerDialog(event.id, this.events.confirm(dialog).then((confirmed) => ({ confirmed })));
				} else if (method === "select") {
					const options = Array.isArray(event.options) ? event.options.map(String) : [];
					this.answerDialog(event.id, this.events.choose({ ...dialog, options }).then((value) => (value === undefined ? { cancelled: true } : { value })));
				} else if (DIALOG_METHODS.has(method)) {
					this.answerDialog(event.id, Promise.resolve({ cancelled: true }));
					report({ type: "notice", text: `Pi asked "${dialog.title}", which needs typed input remote control cannot give yet, so it was cancelled.` });
				} else if (method === "setStatus" && event.statusKey === COMMANDS_CHANGED_STATUS) {
					void this.refreshCommands();
				} else if (method === "notify" && (event.notifyType === "warning" || event.notifyType === "error")) {
					report({ type: "notice", text: String(event.message) });
				}
				return;
			}
		}
	}
}

export class RpcPiSessions implements PiSessionAdapter {
	private readonly options: RpcPiSessionsOptions;

	constructor(options: RpcPiSessionsOptions) {
		this.options = options;
	}

	async create(input: { name: string; repository: Repository; workspace: Workspace }, events: PiSessionEvents): Promise<AgentProcess> {
		const location = { name: input.name, workspace: input.workspace.path, branch: input.workspace.branch, repositoryPath: input.repository.path };
		return this.start(input.workspace.path, ["--name", input.name], location, events);
	}

	async resume(session: AgentSession, events: PiSessionEvents): Promise<AgentProcess> {
		// Pi silently starts a new conversation for a missing file, so require one that exists,
		// unless Pi never wrote it: `--session-id` then restarts the conversation under its own id.
		const args = await this.hasHistory(session)
			? ["--session", session.piSessionFile!]
			: session.unprompted ? ["--session-id", session.piSessionId, "--name", session.name] : undefined;
		if (!args) throw new Error(`The Pi history of ${session.name} was not found.`);
		const agent = await this.start(session.workspace, args, session, events);
		if (agent.id !== session.piSessionId) {
			await agent.close();
			throw new Error(`Pi resumed session ${agent.id} instead of ${session.piSessionId}.`);
		}
		return agent;
	}

	async hasHistory(session: AgentSession): Promise<boolean> {
		if (!session.piSessionFile) return false;
		return access(session.piSessionFile).then(() => true, () => false);
	}

	private async start(cwd: string, args: string[], location: Location, events: PiSessionEvents): Promise<AgentProcess> {
		const agent = new RpcAgent(this.options, cwd, args, location, events);
		await agent.start(this.options.startTimeoutMs ?? DEFAULT_START_TIMEOUT_MS);
		return agent;
	}
}
