/**
 * Recognizes tool calls that need the owner's approval while a conversation is
 * remote-controlled: merges, branch deletions, deployments, and privileged commands.
 *
 * This guards against an agent doing one of these by mistake, not against an agent
 * set on evading it: a script that merges or deploys internally is not recognized.
 */

export type SensitiveKind = "merge" | "branch-deletion" | "deployment" | "privileged";

export type SensitiveOperation = { kind: SensitiveKind; title: string; detail: string };

const TITLES: Record<SensitiveKind, string> = {
	merge: "Approve merge?",
	"branch-deletion": "Approve branch deletion?",
	deployment: "Approve deployment?",
	privileged: "Approve privileged command?",
};

/** Tools that are sensitive whatever their arguments. */
const SENSITIVE_TOOLS: Record<string, { kind: SensitiveKind; detail: string }> = {
	merge_this: { kind: "merge", detail: "merge_this: commit, open a PR, squash-merge it, and delete the branch" },
};

const PRIVILEGED = new Set(["sudo", "doas", "pkexec", "run0", "su"]);
/**
 * Commands that run the rest of their words as a command: the options that take a
 * separate value, and how many operands come before the command, like timeout's duration.
 */
const WRAPPERS: Record<string, { valueOptions?: ReadonlySet<string>; operands?: number }> = {
	env: { valueOptions: new Set(["-u", "--unset", "-C", "--chdir"]) },
	nice: { valueOptions: new Set(["-n", "--adjustment"]) },
	ionice: { valueOptions: new Set(["-c", "-n", "-p", "--class", "--classdata"]) },
	timeout: { valueOptions: new Set(["-s", "--signal", "-k", "--kill-after"]), operands: 1 },
	time: { valueOptions: new Set(["-f", "--format", "-o", "--output"]) },
	xargs: { valueOptions: new Set(["-n", "-I", "-L", "-P", "-d", "-s", "-E", "-a", "--max-args", "--max-procs", "--delimiter", "--arg-file"]) },
	exec: { valueOptions: new Set(["-a"]) },
	command: {},
	builtin: {},
	nohup: {},
	stdbuf: {},
};
/** Shells whose `-c` script is read as a command line of its own. */
const SHELLS = new Set(["sh", "bash", "zsh", "dash", "ksh", "fish"]);
/** gh options that take a separate value before the subcommand. */
const GH_VALUE_OPTIONS = new Set(["-R", "--repo", "--hostname"]);
/** Task runners whose target names a deployment when it says so, like `npm run deploy`. */
const RUNNERS = new Set(["npm", "pnpm", "yarn", "bun", "make", "just", "task", "mise", "rake"]);
/** CLIs whose `deploy` subcommand deploys. */
const DEPLOY_CLIS = new Set(["fly", "flyctl", "firebase", "vercel", "netlify", "serverless", "sls", "wrangler", "railway", "gcloud", "heroku"]);
const DEPLOY_SUBCOMMANDS: Record<string, Set<string>> = {
	terraform: new Set(["apply", "destroy"]),
	tofu: new Set(["apply", "destroy"]),
	kubectl: new Set(["apply", "rollout", "replace", "scale", "delete"]),
	helm: new Set(["install", "upgrade", "uninstall", "rollback"]),
	pulumi: new Set(["up", "destroy"]),
	docker: new Set(["push"]),
	podman: new Set(["push"]),
	cargo: new Set(["publish"]),
};
const PUBLISHERS = new Set(["npm", "pnpm", "yarn", "bun"]);
/** Git options that take a separate value before the subcommand. */
const GIT_VALUE_OPTIONS = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]);

/** The operation a tool call would perform, when it is one the owner must approve. */
export function sensitiveOperation(toolName: string, input: unknown): SensitiveOperation | undefined {
	const tool = SENSITIVE_TOOLS[toolName];
	if (tool) return { kind: tool.kind, title: TITLES[tool.kind], detail: tool.detail };
	if (toolName !== "bash") return undefined;
	const command = (input as { command?: unknown } | undefined)?.command;
	if (typeof command !== "string") return undefined;
	const kind = classifyLine(command);
	return kind && { kind, title: TITLES[kind], detail: command.trim() };
}

/** The first sensitive operation among a shell line's commands. */
function classifyLine(line: string): SensitiveKind | undefined {
	for (const words of commands(line)) {
		const kind = classify(words);
		if (kind) return kind;
	}
	return undefined;
}

/**
 * Splits a shell command line into simple commands, each as its words. Quotes are
 * respected; `;`, `&`, `|`, newlines, parentheses, `$(`, and backticks separate commands.
 */
function commands(line: string): string[][] {
	const result: string[][] = [];
	let words: string[] = [];
	let word = "";
	let quote: "'" | "\"" | undefined;
	let quoted = false;
	const endWord = () => {
		if (word || quoted) words.push(word);
		word = "";
		quoted = false;
	};
	const endCommand = () => {
		endWord();
		if (words.length) result.push(words);
		words = [];
	};
	for (let index = 0; index < line.length; index++) {
		const char = line[index];
		if (quote === "'") {
			if (char === "'") quote = undefined;
			else word += char;
			continue;
		}
		if (char === "`" || (char === "$" && line[index + 1] === "(")) {
			endCommand();
			if (char === "$") index++;
			continue;
		}
		if (quote === "\"") {
			if (char === "\"") quote = undefined;
			else if (char === "\\" && index + 1 < line.length) word += line[++index];
			else word += char;
			continue;
		}
		if (char === "'" || char === "\"") {
			quote = char;
			quoted = true;
		} else if (char === "\\" && index + 1 < line.length) {
			word += line[++index];
		} else if (/[;&|\n()]/.test(char)) {
			endCommand();
		} else if (/\s/.test(char)) {
			endWord();
		} else {
			word += char;
		}
	}
	endCommand();
	return result;
}

function basename(word: string): string {
	return word.split("/").pop() ?? word;
}

/** Skips a command's leading options, including the values of `valueOptions`, then `operands` operands. */
function skipOptions(words: string[], valueOptions: ReadonlySet<string> = new Set(), operands = 0): string[] {
	let index = 0;
	while (index < words.length && words[index].startsWith("-") && words[index] !== "-") index += valueOptions.has(words[index]) ? 2 : 1;
	return words.slice(index + operands);
}

function classify(words: string[]): SensitiveKind | undefined {
	let rest = words;
	for (;;) {
		while (rest.length && /^[A-Za-z_]\w*=/.test(rest[0])) rest = rest.slice(1);
		const name = basename(rest[0] ?? "");
		const wrapper = WRAPPERS[name];
		if (!wrapper) break;
		// `command -v sudo` looks a command up without running it.
		if (name === "command" && rest.slice(1).some((word) => word === "-v" || word === "-V")) return undefined;
		rest = skipOptions(rest.slice(1), wrapper.valueOptions, wrapper.operands);
	}
	const [command = "", ...args] = rest.map((word, index) => (index === 0 ? basename(word) : word));
	if (PRIVILEGED.has(command)) return "privileged";
	if (SHELLS.has(command)) {
		const script = args.findIndex((arg) => /^-[a-zA-Z]*c[a-zA-Z]*$/.test(arg));
		return script === -1 || args[script + 1] === undefined ? undefined : classifyLine(args[script + 1]);
	}
	if (command === "eval") return classifyLine(args.join(" "));
	if (command === "git") return classifyGit(args);
	if (command === "gh") return classifyGh(skipOptions(args, GH_VALUE_OPTIONS));
	if (/deploy/i.test(command)) return "deployment";
	const positional = args.filter((arg) => !arg.startsWith("-"));
	if (PUBLISHERS.has(command) && positional[0] === "publish") return "deployment";
	if (RUNNERS.has(command) && positional.some((arg) => /(^|[:_-])deploy($|[:_-])/i.test(arg))) return "deployment";
	if (DEPLOY_CLIS.has(command) && positional.includes("deploy")) return "deployment";
	if (DEPLOY_SUBCOMMANDS[command]?.has(positional[0])) return "deployment";
	if (command === "vercel" && args.includes("--prod")) return "deployment";
	return undefined;
}

function classifyGh(args: string[]): SensitiveKind | undefined {
	const [group, action] = args;
	if (group === "pr" && action === "merge") return "merge";
	if (group === "release" && action === "create") return "deployment";
	if (group === "api") {
		const method = args.findIndex((arg) => arg === "-X" || arg === "--method");
		const deletes = (method !== -1 && /^delete$/i.test(args[method + 1] ?? "")) || args.some((arg) => /^(-XDELETE|--method=DELETE)$/i.test(arg));
		if (deletes && args.some((arg) => /git\/refs\/heads\//.test(arg))) return "branch-deletion";
	}
	return undefined;
}

function classifyGit(args: string[]): SensitiveKind | undefined {
	const [subcommand, ...rest] = skipOptions(args, GIT_VALUE_OPTIONS);
	if (subcommand === "merge") return rest.some((arg) => arg === "--abort" || arg === "--quit") ? undefined : "merge";
	if (subcommand === "branch" && rest.some((arg) => arg === "--delete" || /^-[a-zA-Z]*[dD]/.test(arg))) return "branch-deletion";
	if (subcommand === "push") {
		// --prune and --mirror delete remote branches that have no local counterpart.
		if (rest.some((arg) => ["--delete", "-d", "--prune", "--mirror"].includes(arg))) return "branch-deletion";
		if (rest.filter((arg) => !arg.startsWith("-")).slice(1).some((refspec) => refspec.startsWith(":"))) return "branch-deletion";
	}
	return undefined;
}
