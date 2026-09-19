import assert from "node:assert/strict";
import test from "node:test";
import { createTelegramBotApi } from "./telegram.ts";

type Call = { url: string; body: Record<string, unknown> };

function fakeFetch(results: Record<string, unknown>, calls: Call[]): typeof fetch {
	return (async (url: string, init: RequestInit) => {
		const method = url.split("/").pop()!;
		calls.push({ url, body: JSON.parse(String(init.body)) });
		const result = results[method];
		const payload = result instanceof Error
			? { ok: false, error_code: 401, description: result.message }
			: { ok: true, result };
		return new Response(JSON.stringify(payload), { status: result instanceof Error ? 401 : 200 });
	}) as typeof fetch;
}

test("maps Bot API payloads to remote-control types", async () => {
	const calls: Call[] = [];
	const api = createTelegramBotApi("123:secret", fakeFetch({
		getUpdates: [{
			update_id: 7,
			message: {
				message_id: 3, message_thread_id: 501, is_topic_message: true, text: "hi",
				from: { id: 42, is_bot: false, username: "owner" },
				chat: { id: -1001, type: "supergroup", title: "Pi", is_forum: true },
			},
		}],
		getChatMember: { status: "administrator", can_manage_topics: true },
		createForumTopic: { message_thread_id: 9 },
		sendMessage: { message_id: 77 },
		editMessageText: true,
		editForumTopic: true,
		deleteForumTopic: true,
	}, calls));

	assert.deepEqual(await api.getUpdates({ offset: 5, timeoutSeconds: 25 }), [{
		updateId: 7,
		message: {
			messageId: 3, threadId: 501, text: "hi",
			from: { id: 42, isBot: false, username: "owner" },
			senderChatId: undefined,
			chat: { id: -1001, type: "supergroup", title: "Pi", username: undefined, isForum: true },
		},
	}]);
	assert.deepEqual(calls[0].body, { offset: 5, timeout: 25, allowed_updates: ["message", "callback_query"] });
	assert.equal(calls[0].url, "https://api.telegram.org/bot123:secret/getUpdates");
	assert.deepEqual(await api.getChatMember(-1001, 1000), { status: "administrator", canManageTopics: true });
	assert.deepEqual(await api.createForumTopic(-1001, "control"), { threadId: 9 });
	assert.deepEqual(await api.sendMessage({ chatId: -1001, threadId: 9, text: "hi" }), { messageId: 77 });
	await api.editMessageText({ chatId: -1001, messageId: 77, text: "edited" });
	await api.editForumTopic({ chatId: -1001, threadId: 9, name: "renamed" });
	await api.deleteForumTopic({ chatId: -1001, threadId: 9 });
	assert.deepEqual(calls.slice(-4).map((call) => [call.url.split("/").pop(), call.body]), [
		["sendMessage", { chat_id: -1001, message_thread_id: 9, text: "hi" }],
		["editMessageText", { chat_id: -1001, message_id: 77, text: "edited" }],
		["editForumTopic", { chat_id: -1001, message_thread_id: 9, name: "renamed" }],
		["deleteForumTopic", { chat_id: -1001, message_thread_id: 9 }],
	]);
});

test("replies in the General topic are not attributed to a topic thread", async () => {
	const api = createTelegramBotApi("123:secret", fakeFetch({
		getUpdates: [{
			update_id: 8,
			message: { message_id: 4, message_thread_id: 3, text: "reply", from: { id: 42, is_bot: false }, chat: { id: -1001, type: "supergroup", is_forum: true } },
		}],
	}, []));
	const [update] = await api.getUpdates({ timeoutSeconds: 0 });
	assert.equal(update.message?.threadId, undefined);
});

test("exposes Telegram's retry_after on rate-limit errors", async () => {
	const fetchImpl = (async () => new Response(JSON.stringify({ ok: false, error_code: 429, description: "Too Many Requests", parameters: { retry_after: 7 } }), { status: 429 })) as unknown as typeof fetch;
	const api = createTelegramBotApi("123:secret", fetchImpl);
	await assert.rejects(api.sendMessage({ chatId: 1, text: "x" }), { errorCode: 429, retryAfter: 7 });
});

test("reports Telegram errors without leaking the bot token", async () => {
	const api = createTelegramBotApi("123:secret", fakeFetch({ getMe: new Error("Unauthorized") }, []));
	await assert.rejects(api.getMe(), (error: Error) => /Unauthorized/.test(error.message) && !error.message.includes("secret"));
});

test("maps inline buttons, button presses, and the command menu", async () => {
	const calls: Call[] = [];
	const api = createTelegramBotApi("123:secret", fakeFetch({
		getUpdates: [{
			update_id: 9,
			callback_query: {
				id: "cb-1", data: "rc:abc:0",
				from: { id: 42, is_bot: false, username: "owner" },
				message: { message_id: 77, message_thread_id: 501, is_topic_message: true, chat: { id: -1001, type: "supergroup", is_forum: true } },
			},
		}],
		sendMessage: { message_id: 77 },
		editMessageText: true,
		answerCallbackQuery: true,
		setMyCommands: true,
	}, calls));

	assert.deepEqual(await api.getUpdates({ timeoutSeconds: 0 }), [{
		updateId: 9,
		message: undefined,
		callbackQuery: { id: "cb-1", data: "rc:abc:0", from: { id: 42, isBot: false, username: "owner" }, message: { messageId: 77, chatId: -1001, threadId: 501 } },
	}]);
	await api.sendMessage({ chatId: -1001, threadId: 501, text: "Approve?", buttons: [[{ text: "Approve", data: "rc:abc:0" }, { text: "Deny", data: "rc:abc:1" }]] });
	await api.editMessageText({ chatId: -1001, messageId: 77, text: "Approved.", buttons: [] });
	await api.answerCallbackQuery({ id: "cb-1", text: "Approved." });
	await api.setMyCommands({ chatId: -1001, commands: [{ command: "rc", description: "Remote control" }] });
	assert.deepEqual(calls.slice(1).map((call) => [call.url.split("/").pop(), call.body]), [
		["sendMessage", {
			chat_id: -1001, message_thread_id: 501, text: "Approve?",
			reply_markup: { inline_keyboard: [[{ text: "Approve", callback_data: "rc:abc:0" }, { text: "Deny", callback_data: "rc:abc:1" }]] },
		}],
		["editMessageText", { chat_id: -1001, message_id: 77, text: "Approved.", reply_markup: { inline_keyboard: [] } }],
		["answerCallbackQuery", { callback_query_id: "cb-1", text: "Approved." }],
		["setMyCommands", { commands: [{ command: "rc", description: "Remote control" }], scope: { type: "chat", chat_id: -1001 } }],
	]);
});
