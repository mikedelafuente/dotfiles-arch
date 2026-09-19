/**
 * Questions the owner answers with Telegram inline buttons: approvals of sensitive
 * operations and selections of a repository or agent session.
 *
 * Every question is single-use and expires. It is bound to the owner, the topic it
 * was asked in, and the operation it asks about: a press by anyone else, from
 * another topic or chat, or after the operation stopped applying is refused.
 */
import { randomBytes } from "node:crypto";
import type { InlineButton } from "./coordinator.ts";

export type PromptChoice = {
	label: string;
	/** Shown to the owner once pressed, e.g. "Approved". Defaults to the label. */
	notice?: string;
};

export type PromptBinding = {
	ownerId: number;
	chatId: number;
	/** The topic the question was asked in; undefined for the General topic. */
	threadId?: number;
	/** What is approved or chosen, for the record of how the question ended. */
	operation: string;
	/** Checked when a button is pressed: false once the operation no longer applies, e.g. the agent session was rebound. */
	stillValid?(): boolean;
};

export type PromptOutcome =
	| { kind: "answered"; choice: number; notice: string }
	| { kind: "expired" | "cancelled" | "invalidated" };

export type ButtonPress = { data: string; userId: number; chatId?: number; threadId?: number };

type Pending = {
	binding: PromptBinding;
	choices: PromptChoice[];
	expiresAt: number;
	timer: ReturnType<typeof setTimeout>;
	settle(outcome: PromptOutcome): void;
};

const PREFIX = "rc:";
const NO_LONGER_VALID = "This button is no longer valid.";
const LABEL_LENGTH = 60;

export class OwnerPrompts {
	private readonly pending = new Map<string, Pending>();
	private readonly now: () => number;

	constructor(now: () => number) {
		this.now = now;
	}

	/**
	 * Opens a question with one button per choice, laid out in `rows`. `answer`
	 * resolves with how it ended: the chosen index, or why there was none.
	 */
	open(binding: PromptBinding, rows: PromptChoice[][], ttlMs: number): { buttons: InlineButton[][]; answer: Promise<PromptOutcome>; cancel(): void } {
		const token = randomBytes(12).toString("base64url");
		const choices = rows.flat();
		let resolve!: (outcome: PromptOutcome) => void;
		const answer = new Promise<PromptOutcome>((done) => { resolve = done; });
		const timer = setTimeout(() => this.settle(token, { kind: "expired" }), ttlMs);
		timer.unref?.();
		this.pending.set(token, { binding, choices, expiresAt: this.now() + ttlMs, timer, settle: resolve });
		let index = 0;
		const buttons = rows.map((row) => row.map((choice) => ({ text: shorten(choice.label), data: `${PREFIX}${token}:${index++}` })));
		return { buttons, answer, cancel: () => this.settle(token, { kind: "cancelled" }) };
	}

	/** Whether callback data belongs to remote control's buttons. */
	static owns(data: string | undefined): boolean {
		return data?.startsWith(PREFIX) ?? false;
	}

	/** Validates a button press and answers the question it belongs to; returns the notice to show the presser. */
	press(press: ButtonPress): string {
		const [, token = "", choice = ""] = /^rc:([\w-]+):(\d+)$/.exec(press.data) ?? [];
		const pending = this.pending.get(token);
		const index = Number(choice);
		if (!pending || !pending.choices[index]) return NO_LONGER_VALID;
		const { binding } = pending;
		// Not settled: the owner can still answer the question where it was asked.
		if (press.userId !== binding.ownerId) return "Not authorized: only the owner can answer this.";
		if (press.chatId !== binding.chatId || press.threadId !== binding.threadId) return NO_LONGER_VALID;
		if (this.now() > pending.expiresAt) {
			this.settle(token, { kind: "expired" });
			return "This request expired, so nothing was done.";
		}
		if (binding.stillValid && !binding.stillValid()) {
			this.settle(token, { kind: "invalidated" });
			return NO_LONGER_VALID;
		}
		const notice = pending.choices[index].notice ?? pending.choices[index].label;
		this.settle(token, { kind: "answered", choice: index, notice });
		return notice;
	}

	/** Cancels every open question `matches` selects, e.g. those of a topic that stopped being routed. */
	cancelWhere(matches: (binding: PromptBinding) => boolean): void {
		for (const [token, pending] of this.pending) if (matches(pending.binding)) this.settle(token, { kind: "cancelled" });
	}

	private settle(token: string, outcome: PromptOutcome): void {
		const pending = this.pending.get(token);
		if (!pending) return;
		this.pending.delete(token);
		clearTimeout(pending.timer);
		pending.settle(outcome);
	}
}

function shorten(label: string): string {
	return label.length > LABEL_LENGTH ? `${label.slice(0, LABEL_LENGTH - 1)}…` : label;
}
