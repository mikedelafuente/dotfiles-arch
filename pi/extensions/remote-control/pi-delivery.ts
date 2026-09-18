/**
 * Delivers remote messages into the running Pi conversation without losing them.
 *
 * Pi rejects a prompt while it compacts, and two prompts sent before the first run
 * starts race each other; `pi.sendUserMessage` reports both only as extension
 * errors. Messages are therefore held while a prompt is starting or compaction is
 * running, then delivered in order.
 */

export type DeliverAs = "steer" | "followUp";

export type PiDeliveryOptions = {
	/** `pi.sendUserMessage` with a delivery mode; Pi ignores the mode when idle and starts a run. */
	send(text: string, deliverAs: DeliverAs): void;
	isIdle(): boolean;
	/** Gives up waiting for a run or compaction that never reports back. */
	timeoutMs?: number;
};

const DEFAULT_TIMEOUT_MS = 30_000;

export class PiDelivery {
	private readonly options: PiDeliveryOptions;
	private readonly held: [text: string, deliverAs: DeliverAs][] = [];
	private starting?: ReturnType<typeof setTimeout>;
	private compacting?: ReturnType<typeof setTimeout>;

	constructor(options: PiDeliveryOptions) {
		this.options = options;
	}

	/** False while messages are being held. */
	isReady(): boolean {
		return !this.starting && !this.compacting;
	}

	prompt(text: string): void {
		this.deliver(text, "steer");
	}

	steer(text: string): void {
		this.deliver(text, "steer");
	}

	followUp(text: string): void {
		this.deliver(text, "followUp");
	}

	/** Pi's `agent_start`: a run is active, so queued messages can steer or follow it. */
	runStarted(): void {
		clearTimeout(this.starting);
		this.starting = undefined;
		this.flush();
	}

	compactionStarted(): void {
		clearTimeout(this.compacting);
		this.compacting = this.timeout(() => this.compactionEnded());
	}

	compactionEnded(): void {
		clearTimeout(this.compacting);
		this.compacting = undefined;
		this.flush();
	}

	dispose(): void {
		clearTimeout(this.starting);
		clearTimeout(this.compacting);
		this.held.length = 0;
	}

	private deliver(text: string, deliverAs: DeliverAs): void {
		this.held.push([text, deliverAs]);
		this.flush();
	}

	private flush(): void {
		while (this.isReady() && this.held.length) {
			const [text, deliverAs] = this.held.shift()!;
			// From idle, this message starts a run; later ones wait until it has.
			const startsRun = this.options.isIdle();
			this.options.send(text, deliverAs);
			if (startsRun) this.starting = this.timeout(() => this.runStarted());
		}
	}

	private timeout(callback: () => void): ReturnType<typeof setTimeout> {
		const timer = setTimeout(callback, this.options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
		timer.unref?.();
		return timer;
	}
}
