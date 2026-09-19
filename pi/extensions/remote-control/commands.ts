/**
 * The commands a session topic accepts: remote control's own `/rc` commands, a
 * maintained catalog of Pi built-ins, and the commands Pi discovered.
 *
 * Pi's command discovery (RPC `get_commands`, `pi.getCommands()`) lists extension
 * commands, prompt templates, and skills, but no built-ins: those are handled by
 * the interactive TUI and do nothing when sent as a prompt. The catalog below lists
 * the built-ins remote control runs itself, through RPC or the extension API.
 */
import type { LivePiSession, PiCommand } from "./coordinator.ts";
import { condenseForTelegram } from "./messages.ts";

export const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;

export type ThinkingLevel = (typeof THINKING_LEVELS)[number];

export type BuiltinName = "compact" | "thinking";

type CatalogEntry = { usage: string; description: string };

type Builtin = CatalogEntry & {
	/** The only arguments the built-in accepts, checked before it runs. */
	requiresArgument?: readonly string[];
	/** Runs the built-in in a session; resolves with the reply for its topic. */
	run(pi: LivePiSession, args: string): Promise<string>;
};

/**
 * Pi built-ins that remote control can run; kept in step with Pi's
 * BUILTIN_SLASH_COMMANDS by hand. `/reload` is left out on purpose: RPC has no
 * reload command, and reloading the local Pi tears this extension down with the bridge.
 */
export const REMOTE_BUILTINS: Record<BuiltinName, Builtin> = {
	compact: {
		usage: "/rc compact [instructions]",
		description: "Compact the session context",
		async run(pi, args) {
			const { tokensBefore, estimatedTokensAfter } = await pi.compact(args || undefined);
			return tokensBefore === undefined
				? "Compacted the context."
				: `Compacted the context from ${tokensBefore} to about ${estimatedTokensAfter ?? "?"} tokens.`;
		},
	},
	thinking: {
		usage: "/rc thinking <level>",
		description: `Set the thinking level: ${THINKING_LEVELS.join(", ")}`,
		requiresArgument: THINKING_LEVELS,
		async run(pi, args) {
			await pi.setThinkingLevel(args as ThinkingLevel);
			return `Thinking level set to ${args}.`;
		},
	},
};

/** The reply to an extension command sent from Telegram. */
export function extensionCommandRefusal(name: string): string {
	return `/${name} is an extension command, which runs only in a local Pi: remote control cannot approve what it does.`;
}

export const TOPIC_COMMANDS: CatalogEntry[] = [
	{ usage: "/rc followup <message>", description: "Queue work after the current run" },
	{ usage: "/rc stop-agent", description: "Abort the current run, after you confirm" },
	{ usage: "/rc commands", description: "This list" },
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

const line = ({ usage, description }: CatalogEntry) => `${usage}: ${description}`;

/** Everything a session topic accepts, for `/rc commands`. */
export function renderCommands(discovered: PiCommand[]): string {
	const runnable = discovered.filter((command) => command.source !== "extension");
	const local = discovered.filter((command) => command.source === "extension");
	const sections = [
		["Commands in this topic:", ...TOPIC_COMMANDS.map(line)],
		["Pi built-ins:", ...Object.values(REMOTE_BUILTINS).map(line)],
	];
	if (runnable.length) {
		sections.push([
			"Prompt templates and skills (also as /<name>):",
			...runnable.map((command) => line({ usage: `/rc ${command.name}`, description: command.description || command.source })),
		]);
	}
	if (local.length) {
		sections.push([
			"Extension commands, local Pi only:",
			...local.map((command) => (command.description ? `/${command.name}: ${command.description}` : `/${command.name}`)),
		]);
	}
	sections.push(["Any other message is a prompt, or steers the current run."]);
	return condenseForTelegram(sections.map((section) => section.join("\n")).join("\n\n"));
}
