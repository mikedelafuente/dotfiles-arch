/** Pure text formatting for session topics: commands in, progress and responses out. */

/** Room left under Telegram's 4096-character message limit for the truncation note. */
export const RESPONSE_BUDGET = 3500;
const TOOL_DETAIL_LENGTH = 80;
const PROMPT_LENGTH = 200;
const VISIBLE_TOOLS = 8;

export const SESSION_TOPIC_HELP = "Send a message to prompt or steer this agent, or /rc followup <message> to queue work after the current run.";

export type SessionTopicInput =
	| { kind: "message"; text: string }
	| { kind: "followUp"; text: string }
	| { kind: "invalid"; reply: string };

/** Parses an owner message in a session topic. Only `/rc` is reserved; other text goes to Pi verbatim. */
export function parseSessionTopicInput(text: string): SessionTopicInput {
	const command = /^\/rc(?:@\w+)?(?:\s+([\s\S]*))?$/i.exec(text.trim());
	if (!command) return { kind: "message", text };
	const [, name = "", argument = ""] = /^(\S*)\s*([\s\S]*)$/.exec((command[1] ?? "").trim()) ?? [];
	if (name.toLowerCase() === "followup") {
		return argument.trim() ? { kind: "followUp", text: argument.trim() } : { kind: "invalid", reply: "Usage: /rc followup <message>" };
	}
	return { kind: "invalid", reply: `Unknown command in a session topic. ${SESSION_TOPIC_HELP}` };
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

export function formatDuration(ms: number): string {
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

/**
 * Condenses a response to fit one Telegram message by keeping its opening, cut at
 * a paragraph, line, or word boundary. The full text stays only in the Pi session.
 */
export function condenseForTelegram(text: string, budget = RESPONSE_BUDGET): string {
	const trimmed = text.trim();
	if (trimmed.length <= budget) return trimmed;
	const boundary = [trimmed.lastIndexOf("\n\n", budget), trimmed.lastIndexOf("\n", budget), trimmed.lastIndexOf(" ", budget)]
		.find((index) => index >= budget / 2) ?? budget;
	const kept = trimmed.slice(0, boundary).trimEnd();
	return `${kept}\n\n… ${trimmed.length - kept.length} more characters: the full response is in the Pi session.`;
}

/** Telegram topic names are limited to 128 characters. */
export function topicTitle(repositoryName: string, sessionName: string, branch: string): string {
	const title = `${repositoryName} / ${sessionName} / ${branch}`;
	return title.length > 128 ? `${title.slice(0, 127)}…` : title;
}
