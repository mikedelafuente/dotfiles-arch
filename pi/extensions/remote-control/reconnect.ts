/**
 * Whether remote control restarts in the runtime that replaces this one.
 *
 * Pi's `/new` and `/reload` tear down this extension's runtime, and remote control
 * with it, then load the extension again (its module re-imported, so module state is
 * lost) and emit `session_start` with the same reason. Remote control that was running
 * then starts again, exposing the new conversation as `/rc start` does. The flag lives
 * on an object that outlives the module, `globalThis` in Pi.
 */

import type { SessionShutdownEvent, SessionStartEvent } from "@earendil-works/pi-coding-agent";

type ShutdownReason = SessionShutdownEvent["reason"];
type StartReason = SessionStartEvent["reason"];

const KEY = Symbol.for("pi-remote-control.reconnect");

type Store = { [KEY]?: ShutdownReason };

/** Only a new conversation or a reload continues in this Pi; quit, resume, and fork never reconnect. */
const RECONNECTING: readonly ShutdownReason[] = ["new", "reload"];

/** Records, on `session_shutdown`, whether the next runtime restarts remote control. */
export function rememberForReconnect(store: object, reason: ShutdownReason, bridgeRunning: boolean): void {
	const flag = store as Store;
	if (bridgeRunning && RECONNECTING.includes(reason)) flag[KEY] = reason;
	else delete flag[KEY];
}

/** On `session_start`: whether to restart remote control. The flag is consumed either way. */
export function takeReconnect(store: object, reason: StartReason): boolean {
	const flag = store as Store;
	const remembered = flag[KEY];
	delete flag[KEY];
	return remembered !== undefined && remembered === reason;
}
