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
/** Prefixes that run the rest of the words as the command. */
const WRAPPERS = new Set(["env", "command", "exec", "time", "nohup", "nice", "builtin"]);
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
	for (const words of commands(command)) {
		const kind = classify(words);
		if (kind) return { kind, title: TITLES[kind], detail: command.trim() };
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

function classify(words: string[]): SensitiveKind | undefined {
	let start = 0;
	while (start < words.length && (/^[A-Za-z_]\w*=/.test(words[start]) || WRAPPERS.has(basename(words[start])))) start++;
	const [command = "", ...args] = words.slice(start).map((word, index) => (index === 0 ? basename(word) : word));
	if (PRIVILEGED.has(command)) return "privileged";
	if (command === "git") return classifyGit(args);
	if (command === "gh") {
		if (args[0] === "pr" && args[1] === "merge") return "merge";
		if (args[0] === "release" && args[1] === "create") return "deployment";
		return undefined;
	}
	if (/deploy/i.test(command)) return "deployment";
	const positional = args.filter((arg) => !arg.startsWith("-"));
	if (PUBLISHERS.has(command) && positional[0] === "publish") return "deployment";
	if (RUNNERS.has(command) && positional.some((arg) => /(^|[:_-])deploy($|[:_-])/i.test(arg))) return "deployment";
	if (DEPLOY_CLIS.has(command) && positional.includes("deploy")) return "deployment";
	if (DEPLOY_SUBCOMMANDS[command]?.has(positional[0])) return "deployment";
	if (command === "vercel" && args.includes("--prod")) return "deployment";
	return undefined;
}

function classifyGit(args: string[]): SensitiveKind | undefined {
	let index = 0;
	while (index < args.length && args[index].startsWith("-")) index += GIT_VALUE_OPTIONS.has(args[index]) ? 2 : 1;
	const subcommand = args[index];
	const rest = args.slice(index + 1);
	if (subcommand === "merge") return rest.some((arg) => arg === "--abort" || arg === "--quit") ? undefined : "merge";
	if (subcommand === "branch" && rest.some((arg) => arg === "--delete" || /^-[a-zA-Z]*[dD]/.test(arg))) return "branch-deletion";
	if (subcommand === "push") {
		if (rest.some((arg) => arg === "--delete" || arg === "-d")) return "branch-deletion";
		if (rest.filter((arg) => !arg.startsWith("-")).slice(1).some((refspec) => refspec.startsWith(":"))) return "branch-deletion";
	}
	return undefined;
}
