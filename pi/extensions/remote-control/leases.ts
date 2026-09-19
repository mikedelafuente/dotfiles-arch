/**
 * Session leases as files: `<directory>/<conversation>/<pid>`, one per Pi process
 * holding that conversation, so one Pi releasing its lease never hides another's.
 * Machine-local; a Pi without this extension, or on another machine, leaves none.
 */
import { readFileSync } from "node:fs";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { SessionLeases } from "./coordinator.ts";

type Lease = { pid: number; startTime?: string };

/** When a process started, from `/proc`, so a reused PID is not mistaken for the lease holder. Undefined off Linux. */
function startTime(pid: number): string | undefined {
	try {
		const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
		// Field 22; the command name (field 2) may contain spaces, so count from its closing parenthesis.
		return stat.slice(stat.lastIndexOf(")") + 2).split(" ")[19];
	} catch {
		return undefined;
	}
}

function isAlive(lease: Lease): boolean {
	try {
		process.kill(lease.pid, 0);
	} catch (error) {
		// EPERM: the process exists but belongs to another user.
		if ((error as NodeJS.ErrnoException).code !== "EPERM") return false;
	}
	return lease.startTime === undefined || startTime(lease.pid) === lease.startTime;
}

/** One directory name per conversation id; `.` is encoded too, so `..` cannot escape. */
function entryName(piSessionId: string): string {
	return encodeURIComponent(piSessionId).replace(/\./g, "%2E");
}

export class SessionLeaseFiles implements SessionLeases {
	private readonly directory: string;
	private readonly pid: number;

	constructor(directory: string, pid = process.pid) {
		this.directory = directory;
		this.pid = pid;
	}

	/** Records that this process has the conversation open. */
	async acquire(piSessionId: string): Promise<void> {
		const directory = join(this.directory, entryName(piSessionId));
		await mkdir(directory, { recursive: true, mode: 0o700 });
		const lease: Lease = { pid: this.pid, startTime: startTime(this.pid) };
		await writeFile(join(directory, String(this.pid)), `${JSON.stringify(lease)}\n`, { mode: 0o600 });
	}

	async release(piSessionId: string): Promise<void> {
		const directory = join(this.directory, entryName(piSessionId));
		await rm(join(directory, String(this.pid)), { force: true });
		// Only succeeds once no other process holds a lease.
		await rm(directory).catch(() => undefined);
	}

	async holders(piSessionId: string): Promise<number[]> {
		const directory = join(this.directory, entryName(piSessionId));
		const entries = await readdir(directory).catch((error: NodeJS.ErrnoException) => {
			if (error.code === "ENOENT") return [];
			throw error;
		});
		const live: number[] = [];
		for (const entry of entries) {
			const lease = await readFile(join(directory, entry), "utf8")
				.then((text) => JSON.parse(text) as Lease)
				.catch(() => undefined);
			if (typeof lease?.pid !== "number" || String(lease.pid) !== entry) continue;
			if (isAlive(lease)) live.push(lease.pid);
			else await rm(join(directory, entry), { force: true });
		}
		return live.sort((a, b) => a - b);
	}
}
