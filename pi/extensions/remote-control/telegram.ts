/** Telegram Bot API adapter over fetch. No SDK: remote control only needs a handful of methods. */
import type { InlineButton, TelegramBotApi, TelegramChat, TelegramChatMember, TelegramUpdate, TelegramUser } from "./coordinator.ts";

const REQUEST_TIMEOUT_MS = 15_000;

type RawUser = { id: number; is_bot: boolean; username?: string };
type RawChat = { id: number; type: TelegramChat["type"]; title?: string; username?: string; is_forum?: boolean };
type RawMessage = {
	message_id: number;
	message_thread_id?: number;
	is_topic_message?: boolean;
	text?: string;
	from?: RawUser;
	sender_chat?: { id: number };
	chat: RawChat;
};
type RawCallbackQuery = { id: string; from: RawUser; data?: string; message?: RawMessage };
type RawUpdate = { update_id: number; message?: RawMessage; callback_query?: RawCallbackQuery };
type RawChatMember = { status: TelegramChatMember["status"]; can_manage_topics?: boolean };

export class TelegramApiError extends Error {
	readonly errorCode?: number;
	/** Seconds to wait before retrying a rate-limited (429) request. */
	readonly retryAfter?: number;

	constructor(method: string, description: string, errorCode?: number, retryAfter?: number) {
		super(`Telegram ${method} failed: ${description}`);
		this.name = "TelegramApiError";
		this.errorCode = errorCode;
		this.retryAfter = retryAfter;
	}
}

const user = (raw: RawUser): TelegramUser => ({ id: raw.id, isBot: raw.is_bot, username: raw.username });
const chat = (raw: RawChat): TelegramChat => ({ id: raw.id, type: raw.type, title: raw.title, username: raw.username, isForum: raw.is_forum });
// Replies in the General topic carry the reply's root as message_thread_id.
const threadOf = (raw: RawMessage) => (raw.is_topic_message ? raw.message_thread_id : undefined);
/** An empty keyboard removes a message's buttons when it is edited. */
const keyboard = (buttons: InlineButton[][]) => ({ inline_keyboard: buttons.map((row) => row.map(({ text, data }) => ({ text, callback_data: data }))) });

export function createTelegramBotApi(token: string, fetchImpl: typeof fetch = fetch): TelegramBotApi {
	async function call<T>(method: string, body: Record<string, unknown> = {}, options: { timeoutMs?: number; signal?: AbortSignal } = {}): Promise<T> {
		const timeout = AbortSignal.timeout(options.timeoutMs ?? REQUEST_TIMEOUT_MS);
		let response: Response;
		try {
			response = await fetchImpl(`https://api.telegram.org/bot${token}/${method}`, {
				method: "POST",
				headers: { "content-type": "application/json" },
				body: JSON.stringify(body),
				signal: options.signal ? AbortSignal.any([options.signal, timeout]) : timeout,
			});
		} catch (error) {
			if (options.signal?.aborted) throw options.signal.reason;
			// Never include the request URL: it contains the bot token.
			throw new TelegramApiError(method, error instanceof Error ? error.message : String(error));
		}
		const payload = (await response.json().catch(() => ({}))) as {
			ok?: boolean;
			result?: T;
			description?: string;
			error_code?: number;
			parameters?: { retry_after?: number };
		};
		if (!payload.ok) {
			throw new TelegramApiError(method, payload.description ?? `HTTP ${response.status}`, payload.error_code ?? response.status, payload.parameters?.retry_after);
		}
		return payload.result as T;
	}

	return {
		async getMe() {
			return user(await call<RawUser>("getMe"));
		},
		async getUpdates({ offset, timeoutSeconds, signal }) {
			const updates = await call<RawUpdate[]>(
				"getUpdates",
				{ offset, timeout: timeoutSeconds, allowed_updates: ["message", "callback_query"] },
				{ timeoutMs: (timeoutSeconds + 10) * 1000, signal },
			);
			return updates.map((update): TelegramUpdate => {
				const query = update.callback_query;
				return {
					updateId: update.update_id,
					message: update.message && {
						messageId: update.message.message_id,
						threadId: threadOf(update.message),
						text: update.message.text,
						from: update.message.from && user(update.message.from),
						senderChatId: update.message.sender_chat?.id,
						chat: chat(update.message.chat),
					},
					...(query ? {
						callbackQuery: {
							id: query.id,
							data: query.data,
							from: user(query.from),
							message: query.message && { messageId: query.message.message_id, chatId: query.message.chat.id, threadId: threadOf(query.message) },
						},
					} : {}),
				};
			});
		},
		async getChat(chatId) {
			return chat(await call<RawChat>("getChat", { chat_id: chatId }));
		},
		async getChatMember(chatId, userId) {
			const member = await call<RawChatMember>("getChatMember", { chat_id: chatId, user_id: userId });
			return { status: member.status, canManageTopics: member.can_manage_topics };
		},
		async createForumTopic(chatId, name) {
			const topic = await call<{ message_thread_id: number }>("createForumTopic", { chat_id: chatId, name });
			return { threadId: topic.message_thread_id };
		},
		async deleteForumTopic({ chatId, threadId }) {
			await call("deleteForumTopic", { chat_id: chatId, message_thread_id: threadId });
		},
		async editForumTopic({ chatId, threadId, name }) {
			await call("editForumTopic", { chat_id: chatId, message_thread_id: threadId, name });
		},
		async closeForumTopic({ chatId, threadId }) {
			await call("closeForumTopic", { chat_id: chatId, message_thread_id: threadId });
		},
		async reopenForumTopic({ chatId, threadId }) {
			await call("reopenForumTopic", { chat_id: chatId, message_thread_id: threadId });
		},
		async sendMessage({ chatId, threadId, text, buttons }) {
			const message = await call<{ message_id: number }>("sendMessage", {
				chat_id: chatId, message_thread_id: threadId, text, ...(buttons ? { reply_markup: keyboard(buttons) } : {}),
			});
			return { messageId: message.message_id };
		},
		async editMessageText({ chatId, messageId, text, buttons }) {
			await call("editMessageText", { chat_id: chatId, message_id: messageId, text, ...(buttons ? { reply_markup: keyboard(buttons) } : {}) });
		},
		async answerCallbackQuery({ id, text }) {
			await call("answerCallbackQuery", { callback_query_id: id, text });
		},
		async setMyCommands({ chatId, commands }) {
			await call("setMyCommands", { commands, scope: { type: "chat", chat_id: chatId } });
		},
	};
}
