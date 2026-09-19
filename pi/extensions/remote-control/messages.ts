/** Pure text formatting for session and control topics: commands in, progress, responses, and listings out. */
import type { CleanupReport, LeaseHolder, RemoteControlStatus, RepositoryHealth, RepositorySessions, SessionOverview, SessionStatus, StatusReport } from "./coordinator.ts";

/** Room left under Telegram's 4096-character message limit for the truncation note. */
const RESPONSE_BUDGET = 3500;
/** Share of a condensed response kept from its end, where conclusions usually are. */
const TAIL_SHARE = 0.4;
const TOOL_DETAIL_LENGTH = 80;
const PROMPT_LENGTH = 200;
const VISIBLE_TOOLS = 8;

export function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

export const SESSION_TOPIC_HELP = "Send a message to prompt or steer this agent, /rc followup <message> to queue work after the current run, or /rc commands for everything else.";

export type SessionTopicInput =
	| { kind: "message"; text: string }
	| { kind: "followUp"; text: string }
	| { kind: "commands" }
	| { kind: "stop-agent" }
	| { kind: "status" }
	| { kind: "archive" }
	/** `/rc <name> [args]` for any other name: a Pi built-in or a command Pi discovered, resolved by the coordinator. */
	| { kind: "command"; name: string; args: string }
	| { kind: "invalid"; reply: string };

/** `/rc` or `/rc@bot`, with the rest of the message as group 1. */
const RC_COMMAND = /^\/rc(?:@\w+)?(?:\s+([\s\S]*))?$/i;

/** Parses an owner message in a session topic. Only `/rc` is reserved; other text goes to Pi verbatim. */
export function parseSessionTopicInput(text: string): SessionTopicInput {
	const command = RC_COMMAND.exec(text.trim());
	if (!command) return { kind: "message", text };
	const [, name = "", argument = ""] = /^(\S*)\s*([\s\S]*)$/.exec((command[1] ?? "").trim()) ?? [];
	switch (name.toLowerCase()) {
		case "followup":
			return argument.trim() ? { kind: "followUp", text: argument.trim() } : { kind: "invalid", reply: "Usage: /rc followup <message>" };
		case "":
		case "commands":
		case "help":
			return { kind: "commands" };
		case "stop-agent":
			return { kind: "stop-agent" };
		case "status":
			return { kind: "status" };
		case "archive":
			return { kind: "archive" };
		default:
			return { kind: "command", name: name.replace(/^\//, ""), args: argument.trim() };
	}
}

function oneLine(text: string, max: number): string {
	const line = text.trim().split("\n")[0].replace(/\s+/g, " ");
	return line.length > max || text.trim().includes("\n") ? `${line.slice(0, max - 1).trimEnd()}…` : line;
}

/** A tool call as one short line: its name and main argument, never its output. */
export function describeTool(toolName: string, args: unknown): string {
	const fields = args && typeof args === "object" ? (args as Record<string, unknown>) : {};
	const detail = [fields.path, fields.command, fields.pattern, fields.query, fields.url, ...Object.values(fields)]
		.find((value): value is string => typeof value === "string" && value.trim() !== "");
	return detail ? `${toolName}: ${oneLine(detail, TOOL_DETAIL_LENGTH)}` : toolName;
}

function formatDuration(ms: number): string {
	const seconds = Math.max(0, Math.round(ms / 1000));
	if (seconds < 60) return `${seconds}s`;
	if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
	return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

export type ToolProgress = { id: string; label: string; state: "running" | "done" | "failed" };

export type ProgressView = {
	prompt?: string;
	tools: ToolProgress[];
	elapsedMs: number;
	finished?: "done" | "failed";
};

const TOOL_ICON: Record<ToolProgress["state"], string> = { running: "…", done: "✓", failed: "✗" };

/** The single editable status message for one run of work. */
export function renderProgress(view: ProgressView): string {
	const duration = formatDuration(view.elapsedMs);
	const failed = view.tools.filter((tool) => tool.state === "failed").length;
	const calls = `${view.tools.length} tool call${view.tools.length === 1 ? "" : "s"}${failed ? ` (${failed} failed)` : ""}`;
	const header = view.finished === "done"
		? `✅ Done in ${duration} · ${calls}`
		: view.finished === "failed" ? `⚠️ Failed after ${duration} · ${calls}` : `⏳ Working · ${duration}`;
	const lines = [header];
	if (view.prompt) lines.push(`› ${oneLine(view.prompt, PROMPT_LENGTH)}`);
	if (!view.finished) {
		const hidden = view.tools.length - VISIBLE_TOOLS;
		if (hidden > 0) lines.push(`+${hidden} earlier tool call${hidden === 1 ? "" : "s"}`);
		for (const tool of view.tools.slice(-VISIBLE_TOOLS)) lines.push(`${TOOL_ICON[tool.state]} ${tool.label}`);
	}
	return lines.join("\n");
}

/** The offset nearest `limit` (at most `limit`) that falls on a paragraph, line, or word boundary. */
function boundaryBefore(text: string, limit: number): number {
	return [text.lastIndexOf("\n\n", limit), text.lastIndexOf("\n", limit), text.lastIndexOf(" ", limit)]
		.find((index) => index >= limit / 2) ?? limit;
}

/**
 * Condenses a response to fit one Telegram message by keeping its opening and its
 * conclusion, cut at paragraph, line, or word boundaries. The full text stays only
 * in the Pi session.
 */
export function condenseForTelegram(text: string, budget = RESPONSE_BUDGET): string {
	const trimmed = text.trim();
	if (trimmed.length <= budget) return trimmed;
	const tailBudget = Math.floor(budget * TAIL_SHARE);
	const head = trimmed.slice(0, boundaryBefore(trimmed, budget - tailBudget)).trimEnd();
	const reversed = trimmed.split("").reverse().join(""); // UTF-16 units, so offsets map back onto `trimmed`
	const tail = trimmed.slice(trimmed.length - boundaryBefore(reversed, tailBudget)).trimStart();
	const omitted = trimmed.length - head.length - tail.length;
	return `${head}\n\n… ${omitted} characters omitted: the full response is in the Pi session. …\n\n${tail}`;
}

/** Share of the message budget each held message shown in a reconnect summary may use. */
const HELD_MESSAGE_BUDGET = 1000;

/**
 * The one message a session topic gets once Telegram answers again: how long it was
 * unreachable, what the agent is doing now, and the latest `shown` of the messages held
 * meanwhile, each condensed; older ones are only counted.
 */
export function renderHeldSummary(input: { held: string[]; offlineMs: number; now: string; shown: number }): string {
	const { held, shown } = input;
	const left = held.length - shown;
	const lines = [
		`🔌 Telegram was unreachable for about ${formatDuration(input.offlineMs)}; this agent kept running. Now: ${input.now}.`,
		left > 0
			? `${held.length} messages were held; the latest ${shown} follow (${left} earlier message${left === 1 ? "" : "s"} left out, in the Pi session):`
			: `Held while it was unreachable:`,
		...held.slice(-shown).map((text) => condenseForTelegram(text, HELD_MESSAGE_BUDGET)),
	];
	return condenseForTelegram(lines.join("\n\n"));
}

/** A failed run, in one Telegram message. */
export function failureText(error: string): string {
	return condenseForTelegram(`⚠️ Run failed: ${error}`);
}

/** Telegram topic names are limited to 128 characters. */
export function topicTitle(repositoryName: string, sessionName: string, branch: string): string {
	const title = `${repositoryName} / ${sessionName} / ${branch}`;
	return title.length > 128 ? `${title.slice(0, 127)}…` : title;
}

export const CONTROL_TOPIC_HELP = [
	"Remote control commands:",
	"/rc sessions: agent sessions by repository",
	"/rc new <repository> <name>: start an agent in a new worktree and branch; with only <name>, pick the repository",
	"/rc attach <session>: reconnect a disconnected agent session; without <session>, pick one",
	"/rc stop-agent <session>: abort an agent's current run, after you confirm; without <session>, pick one",
	"/rc status: the bridge, repositories, and agent sessions, with their health",
	"/rc archive <session>: close an idle session's topic and stop its Pi, keeping its history, workspace, and branch; without <session>, pick one",
	"/rc cleanup history <session>: delete a disconnected session's Pi history, after you confirm",
	"/rc cleanup workspace <session> [--abandon|--force]: remove a disconnected session's worktree and branch, after you confirm; --abandon for an unmerged branch, --force for uncommitted changes too",
	"In a session topic, /rc commands lists what that agent accepts.",
].join("\n");

export type ControlCommand =
	| { kind: "sessions" }
	/** Without a repository, the owner picks one of the approved repositories. */
	| { kind: "new"; repository?: string; name: string }
	/** Without a session, the owner picks one of the attachable sessions. */
	| { kind: "attach"; session?: string }
	/** Without a session, the owner picks one of the connected sessions. */
	| { kind: "stop-agent"; session?: string }
	| { kind: "status" }
	/** Without a session, the owner picks one of the sessions that can be archived. */
	| { kind: "archive"; session?: string }
	| { kind: "cleanup"; what: "history" | "workspace"; session: string; abandon: boolean; force: boolean }
	| { kind: "invalid"; reply: string };

const CLEANUP_USAGE = "Usage: /rc cleanup history <session>, or /rc cleanup workspace <session> [--abandon|--force]";

/** Parses an owner message in the control topic; undefined when it is not a `/rc` command. */
export function parseControlCommand(text: string): ControlCommand | undefined {
	const command = RC_COMMAND.exec(text.trim());
	if (!command) return undefined;
	const [name = "", ...args] = (command[1] ?? "").trim().split(/\s+/).filter(Boolean);
	switch (name.toLowerCase()) {
		case "sessions":
			return { kind: "sessions" };
		case "new":
			if (!args.length) return { kind: "invalid", reply: "Usage: /rc new <repository> <name>, or /rc new <name> to pick the repository" };
			return args.length === 1 ? { kind: "new", name: args[0] } : { kind: "new", repository: args[0], name: args.slice(1).join(" ") };
		case "attach":
			return { kind: "attach", session: args.join(" ") || undefined };
		case "stop-agent":
			return { kind: "stop-agent", session: args.join(" ") || undefined };
		case "status":
			return { kind: "status" };
		case "archive":
			return { kind: "archive", session: args.join(" ") || undefined };
		case "cleanup": {
			const [what = "", ...rest] = args;
			const flags = rest.filter((arg) => arg.startsWith("--"));
			const session = rest.filter((arg) => !arg.startsWith("--")).join(" ");
			const unknown = flags.filter((flag) => flag !== "--abandon" && flag !== "--force");
			if ((what !== "history" && what !== "workspace") || !session || unknown.length || (what === "history" && flags.length)) {
				return { kind: "invalid", reply: CLEANUP_USAGE };
			}
			return { kind: "cleanup", what, session, abandon: flags.includes("--abandon"), force: flags.includes("--force") };
		}
		default:
			return { kind: "invalid", reply: CONTROL_TOPIC_HELP };
	}
}

/** The branch a new agent session works on: `rc/<name>`, reduced to characters Git and shells never trip over. */
export function sessionBranch(name: string): string | undefined {
	const slug = name.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[-.]+|[-.]+$/g, "").slice(0, 60).replace(/[-.]+$/, "");
	return slug ? `rc/${slug}` : undefined;
}

/** Where a conversation is open: "this Pi", "another Pi (process 123)", or both. */
export function describeOpenIn(holders: LeaseHolder[]): string {
	const others = holders.filter((holder) => !holder.here).map((holder) => holder.pid);
	const places = holders.some((holder) => holder.here) ? ["this Pi"] : [];
	if (others.length === 1) places.push(`another Pi (process ${others[0]})`);
	else if (others.length) places.push(`other Pis (processes ${others.join(", ")})`);
	return places.join(" and ");
}

const STATUS_TEXT: Record<Exclude<SessionStatus, "open">, string> = {
	active: "running",
	disconnected: "disconnected",
	stale: "stale: Pi history not found",
	"missing-workspace": "missing workspace",
};

function statusText(status: SessionStatus, openIn: LeaseHolder[] = [], activity?: SessionOverview["activity"]): string {
	if (status === "open") return `open in ${describeOpenIn(openIn)}`;
	return activity ? `${STATUS_TEXT[status]}, ${activity}` : STATUS_TEXT[status];
}

/** A repository's heading: its name and path, and what is wrong with it. */
function repositoryLine(repository: RepositoryHealth): string {
	return [`${repository.name} (${repository.path})`, !repository.approved && "not approved", !repository.exists && "checkout missing"].filter(Boolean).join(" · ");
}

function sessionLine(session: SessionOverview): string {
	return `${session.name} · ${session.branch} · ${statusText(session.status, session.openIn, session.activity)}`;
}

/** One repository's sessions: archived ones on one line, since they are out of the active view. */
function sessionLines(group: RepositorySessions): string[] {
	const archived = group.sessions.filter((session) => session.archivedAt);
	return [
		repositoryLine(group.repository),
		...group.sessions.filter((session) => !session.archivedAt).flatMap((session) => [
			`• ${sessionLine(session)}`,
			...session.earlierConversations.map((earlier) =>
				`  ↳ earlier: ${earlier.name} · ${earlier.branch} · ${statusText(earlier.status, earlier.openIn)} · /rc attach ${earlier.piSessionId}`),
		]),
		...(archived.length ? [`  archived: ${archived.map(sessionLine).join("; ")}`] : []),
		"",
	];
}

/** Agent sessions grouped by repository, with their earlier conversations, in one Telegram message. */
export function renderSessions(groups: RepositorySessions[]): string {
	if (!groups.length) return "No agent sessions yet. Start one with /rc new <repository> <name>.";
	const lines = groups.flatMap(sessionLines);
	lines.push("Reconnect a disconnected or archived session with /rc attach <session>; one open in another Pi must be closed there first.");
	return condenseForTelegram(lines.join("\n"));
}

/** The bridge in one line: running or not, and whether Telegram answers. */
export function bridgeLine(bridge: RemoteControlStatus): string {
	if (!bridge.running) return "Remote control: stopped";
	const where = [bridge.bot, bridge.group && `in ${bridge.group}`].filter(Boolean).join(" ");
	const telegram = bridge.unreachableSince === undefined
		? "Telegram: connected"
		: `Telegram: unreachable since ${bridge.unreachableSince}, ${bridge.held} message${bridge.held === 1 ? "" : "s"} held`;
	return [`Remote control: running${where ? ` · ${where}` : ""}`, telegram].join(" · ");
}

/** `/rc status`: the bridge, then every approved repository and every agent session, with their health. */
export function renderStatus(report: StatusReport): string {
	const withSessions = new Set(report.sessions.map((group) => group.repository.path));
	const idle = report.repositories.filter((repository) => !withSessions.has(repository.path));
	const lines = [bridgeLine(report.bridge), "", ...report.sessions.flatMap(sessionLines)];
	if (idle.length) lines.push("No agent sessions:", ...idle.map((repository) => `• ${repositoryLine(repository)}`));
	if (!report.repositories.length && !report.sessions.length) lines.push("No repository is approved yet; run /rc in a repository locally.");
	return condenseForTelegram(lines.join("\n").trim());
}

/** `/rc status` in a session topic: the bridge and that one session. */
export function renderSessionStatus(bridge: RemoteControlStatus, session: SessionOverview, repository: RepositoryHealth): string {
	return [
		bridgeLine(bridge),
		sessionLine(session),
		`Workspace: ${session.workspace}${session.status === "missing-workspace" ? " (missing)" : ""}`,
		`Repository: ${repositoryLine(repository)}`,
	].join("\n");
}

/** What a confirmed cleanup did, kept, and could not do. */
export function renderCleanup(report: CleanupReport): string {
	const section = (label: string, items: string[]) => (items.length ? [`${label}:`, ...items.map((item) => `• ${item}`)] : []);
	return condenseForTelegram([
		report.summary,
		...section("Done", report.done),
		...section("Kept", report.kept),
		...section("Failed", report.failed),
		...(report.forgotten ? ["Nothing of it is left, so it is no longer listed in /rc sessions."] : []),
	].join("\n"));
}

type TextBlock = { type: string; text?: string };
export type RunMessage = { role: string; content?: string | TextBlock[]; stopReason?: string; errorMessage?: string };

/** The final assistant message of a run, as the session topic's response. */
export function runResponse(messages: RunMessage[]): { text: string; error?: string; aborted?: boolean } | undefined {
	const last = messages.findLast((message) => message.role === "assistant");
	if (!last) return undefined;
	const text = typeof last.content === "string"
		? last.content
		: (last.content ?? []).filter((block) => block.type === "text").map((block) => block.text ?? "").join("\n");
	if (last.stopReason === "aborted") return { text, aborted: true };
	if (last.stopReason === "error") return { text, error: last.errorMessage || "unknown error" };
	return { text };
}
