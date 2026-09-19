/**
 * The commands a session topic accepts: remote control's own `/rc` commands, a
 * maintained catalog of Pi built-ins, and the commands Pi discovered.
 *
 * Pi's command discovery (RPC `get_commands`, `pi.getCommands()`) lists extension
 * commands, prompt templates, and skills, but no built-ins: those are handled by
 * the interactive TUI and do nothing when sent as a prompt. The catalog below lists
 * the built-ins remote control runs itself, through RPC or the extension API.
 */
import type { LivePiSession, PiCommand, PiSessionInfo } from "./coordinator.ts";
import { condenseForTelegram } from "./messages.ts";

export const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;

export type ThinkingLevel = (typeof THINKING_LEVELS)[number];

export type BuiltinName = "compact" | "thinking" | "model" | "name" | "session" | "new" | "reload";

type CatalogEntry = { name: string; usage: string; description: string };

/** What a built-in runs against: a topic's conversation, and the agent-session bookkeeping only the coordinator can do. */
export type BuiltinTarget = {
	pi: LivePiSession;
	/** Renames the conversation, its agent session, and its topic; resolves with the reply. */
	rename(name: string): Promise<string>;
	/** Starts a new conversation in the workspace and rebinds the topic to it; resolves with the reply. */
	newConversation(): Promise<string>;
	/** Reloads the conversation's Pi; resolves with the reply. */
	reload(): Promise<string>;
};

type Builtin = CatalogEntry & {
	/** The only arguments the built-in accepts, checked before it runs. */
	requiresArgument?: readonly string[];
	/** Runs the built-in; resolves with the reply for its topic. */
	run(target: BuiltinTarget, args: string): Promise<string>;
};

/** `provider/model`, as Pi's `/model` takes it. */
const MODEL_REFERENCE = /^([^/\s]+)\/(\S+)$/;

/**
 * Pi built-ins that remote control can run; kept in step with Pi's
 * BUILTIN_SLASH_COMMANDS by hand. The rest need Pi's terminal (settings, tree,
 * scoped-models, hotkeys), local files or clipboard (export, import, share, copy),
 * provider logins, or pick another session (resume, fork, clone).
 */
export const REMOTE_BUILTINS: Record<BuiltinName, Builtin> = {
	compact: {
		name: "compact",
		usage: "/rc compact [instructions]",
		description: "Compact the session context",
		async run({ pi }, args) {
			const { tokensBefore, estimatedTokensAfter } = await pi.compact(args || undefined);
			return tokensBefore === undefined
				? "Compacted the context."
				: `Compacted the context from ${tokensBefore} to about ${estimatedTokensAfter ?? "?"} tokens.`;
		},
	},
	thinking: {
		name: "thinking",
		usage: "/rc thinking <level>",
		description: `Set the thinking level: ${THINKING_LEVELS.join(", ")}`,
		requiresArgument: THINKING_LEVELS,
		async run({ pi }, args) {
			await pi.setThinkingLevel(args as ThinkingLevel);
			return `Thinking level set to ${args}.`;
		},
	},
	model: {
		name: "model",
		usage: "/rc model [provider/model]",
		description: "Set the model; without one, list the models",
		async run({ pi }, args) {
			if (!args) {
				const { current, available } = await pi.models();
				return condenseForTelegram(`Model: ${current ?? "none"}. Set one with /rc model <provider/model>:\n${available.join("\n")}`);
			}
			const [, provider, modelId] = MODEL_REFERENCE.exec(args) ?? [];
			if (!provider || !modelId) return "Usage: /rc model <provider/model>, e.g. /rc model anthropic/claude-sonnet-5; /rc model lists them.";
			await pi.setModel(provider, modelId);
			return `Model set to ${provider}/${modelId}.`;
		},
	},
	name: {
		name: "name",
		usage: "/rc name <name>",
		description: "Rename the session and its topic",
		async run(target, args) {
			return args ? target.rename(args) : `Usage: /rc name <name>. This session is ${target.pi.name || "unnamed"}.`;
		},
	},
	session: {
		name: "session",
		usage: "/rc session",
		description: "Show session info and usage",
		async run({ pi }) {
			return renderSessionInfo(await pi.info());
		},
	},
	new: {
		name: "new",
		usage: "/rc new",
		description: "Start a new conversation in this workspace; the current one stays attachable",
		run: (target) => target.newConversation(),
	},
	reload: {
		name: "reload",
		usage: "/rc reload",
		description: "Reload extensions, skills, prompts, and context files",
		run: (target) => target.reload(),
	},
};

/** The reply when the current conversation is asked for a built-in that would replace its Pi runtime. */
export function localOnlyBuiltin(name: BuiltinName): string {
	return `/${name} runs only locally for this conversation: it replaces this Pi's extensions, which stops remote control. Run /${name} in Pi, then /rc again.`;
}

/** What the owner approves before an extension command runs. */
export function extensionCommandQuestion(text: string, topicName: string): string {
	return [
		`🔐 Run ${text}?`,
		"Extension commands run outside remote control's approvals: nothing this command does is asked about again.",
		`Agent session: ${topicName}`,
	].join("\n\n");
}

/** Why an extension command sent to an agent as a prompt did not run. */
export function extensionCommandRefusal(name: string): string {
	return `/${name} is an extension command, which runs outside remote control's approvals; send /rc ${name} to run it once you approve.`;
}

/** Remote control's own command: from Telegram it could log remote control out or stop it. */
export const REMOTE_CONTROL_COMMAND = "rc";

export const OWN_COMMAND_REFUSAL = "/rc is remote control's own command and cannot be run from Telegram; use the /rc commands this topic lists.";

/** Remote control's commands in a session topic, each also accepted as `/<name>`. */
export const TOPIC_COMMANDS: CatalogEntry[] = [
	{ name: "commands", usage: "/rc commands", description: "This list" },
	{ name: "followup", usage: "/rc followup <message>", description: "Queue work after the current run" },
	{ name: "stop-agent", usage: "/rc stop-agent", description: "Abort the current run, after you confirm" },
];

export function isBuiltin(name: string): name is BuiltinName {
	return Object.hasOwn(REMOTE_BUILTINS, name);
}

/** A usage reply when a built-in's argument is missing or invalid. */
export function builtinArgumentError(name: BuiltinName, args: string): string | undefined {
	const allowed = REMOTE_BUILTINS[name].requiresArgument;
	if (!allowed || allowed.includes(args)) return undefined;
	return `Usage: ${REMOTE_BUILTINS[name].usage}, with one of ${allowed.join(", ")}.`;
}

const line = ({ usage, description }: Pick<CatalogEntry, "usage" | "description">) => `${usage}: ${description}`;

/** Commands the owner can run from Telegram: everything but remote control's own. */
function runnable(discovered: PiCommand[]): PiCommand[] {
	return discovered.filter((command) => command.name !== REMOTE_CONTROL_COMMAND);
}

/** Everything a session topic accepts, for `/rc commands`. */
export function renderCommands(discovered: PiCommand[]): string {
	const expandable = runnable(discovered).filter((command) => command.source !== "extension");
	const extensions = runnable(discovered).filter((command) => command.source === "extension");
	const discoveredLine = (command: PiCommand) => line({ usage: `/rc ${command.name}`, description: command.description || command.source });
	const sections = [
		["Commands in this topic:", ...TOPIC_COMMANDS.map(line)],
		["Pi built-ins:", ...Object.values(REMOTE_BUILTINS).map(line)],
	];
	if (expandable.length) sections.push(["Prompt templates and skills:", ...expandable.map(discoveredLine)]);
	if (extensions.length) sections.push(["Extension commands, run after you approve:", ...extensions.map(discoveredLine)]);
	sections.push(["Every command also works as /<name>, and from the Telegram / menu. Any other message is a prompt, or steers the current run."]);
	return condenseForTelegram(sections.map((section) => section.join("\n")).join("\n\n"));
}

function formatCount(count: number): string {
	return count.toLocaleString("en-US");
}

/** Pi's `/session` output, for a session topic. */
export function renderSessionInfo(info: PiSessionInfo): string {
	const { messages, tokens, context } = info;
	return [
		`Session: ${info.name ?? "unnamed"}`,
		`Id: ${info.id}`,
		info.file && `File: ${info.file}`,
		info.model && `Model: ${info.model}${info.thinkingLevel ? `, thinking ${info.thinkingLevel}` : ""}`,
		`Messages: ${formatCount(messages.user)} user, ${formatCount(messages.assistant)} assistant, ${formatCount(messages.toolCalls)} tool calls`,
		`Tokens: ${formatCount(tokens.input)} input, ${formatCount(tokens.output)} output, ${formatCount(tokens.cacheRead)} cache read, ${formatCount(tokens.cacheWrite)} cache write`,
		`Cost: $${info.cost.toFixed(4)}`,
		context && `Context: ${context.tokens === null ? "unknown until the next response" : formatCount(context.tokens)} of ${formatCount(context.window)} tokens${context.percent === null ? "" : ` (${Math.round(context.percent)}%)`}`,
	].filter(Boolean).join("\n");
}

/** The Telegram `/` menu: at most 100 commands, each named with 1–32 of a–z, 0–9, and _. */
export type MenuCommand = { command: string; description: string };

const MENU_LIMIT = 100;
const MENU_DESCRIPTION_LENGTH = 256;
const RC_MENU_ENTRY: MenuCommand = { command: REMOTE_CONTROL_COMMAND, description: "Remote control: /rc commands in a session topic, /rc help in the control topic" };

/** A command's name in the Telegram menu: `skill:tdd` becomes `skill_tdd`. Undefined when nothing is left of it. */
export function menuName(name: string): string | undefined {
	const mapped = name.toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 32).replace(/_+$/, "");
	return mapped || undefined;
}

/** Every command a session topic accepts, in menu order: its own, the built-ins, then what Pi discovered. */
function catalog(discovered: PiCommand[]): Pick<CatalogEntry, "name" | "description">[] {
	return [
		...TOPIC_COMMANDS,
		...Object.values(REMOTE_BUILTINS),
		...runnable(discovered).map((command) => ({ name: command.name, description: command.description || command.source })),
	];
}

/** Menu names to the command each stands for; on a collision the command listed first keeps the name. */
function menuEntries(discovered: PiCommand[]): Map<string, Pick<CatalogEntry, "name" | "description">> {
	const entries = new Map<string, Pick<CatalogEntry, "name" | "description">>();
	for (const entry of catalog(discovered)) {
		const mapped = menuName(entry.name);
		if (mapped && mapped !== REMOTE_CONTROL_COMMAND && !entries.has(mapped)) entries.set(mapped, entry);
	}
	return entries;
}

/** The group's command menu for the commands its connected conversations discovered. */
export function buildMenu(discovered: PiCommand[]): MenuCommand[] {
	const commands = [...menuEntries(discovered)].map(([command, entry]) => ({
		command,
		description: (entry.description.trim() || entry.name).slice(0, MENU_DESCRIPTION_LENGTH),
	}));
	return [RC_MENU_ENTRY, ...commands].slice(0, MENU_LIMIT);
}

/**
 * The command a `/<name>` message stands for, by its own name or its menu name,
 * with a `@bot` suffix ignored; undefined when it names none.
 */
export function resolveTyped(typed: string, discovered: PiCommand[]): string | undefined {
	const name = typed.replace(/@\w+$/, "");
	const entries = catalog(discovered);
	return entries.find((entry) => entry.name === name)?.name ?? menuEntries(discovered).get(name.toLowerCase())?.name;
}
