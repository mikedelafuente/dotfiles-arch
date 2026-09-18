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
				message_id: 3, message_thread_id: 501, text: "hi",
				from: { id: 42, is_bot: false, username: "owner" },
				chat: { id: -1001, type: "supergroup", title: "Pi", is_forum: true },
			},
		}],
		getChatMember: { status: "administrator", can_manage_topics: true },
		createForumTopic: { message_thread_id: 9 },
	}, calls));

	assert.deepEqual(await api.getUpdates({ offset: 5, timeoutSeconds: 25 }), [{
		updateId: 7,
		message: {
			messageId: 3, threadId: 501, text: "hi",
			from: { id: 42, isBot: false, username: "owner" },
			chat: { id: -1001, type: "supergroup", title: "Pi", username: undefined, isForum: true },
		},
	}]);
	assert.deepEqual(calls[0].body, { offset: 5, timeout: 25, allowed_updates: ["message"] });
	assert.equal(calls[0].url, "https://api.telegram.org/bot123:secret/getUpdates");
	assert.deepEqual(await api.getChatMember(-1001, 1000), { status: "administrator", canManageTopics: true });
	assert.deepEqual(await api.createForumTopic(-1001, "control"), { threadId: 9 });
});

test("reports Telegram errors without leaking the bot token", async () => {
	const api = createTelegramBotApi("123:secret", fakeFetch({ getMe: new Error("Unauthorized") }, []));
	await assert.rejects(api.getMe(), (error: Error) => /Unauthorized/.test(error.message) && !error.message.includes("secret"));
});
