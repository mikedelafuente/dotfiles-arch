/**
 * Ask User extension
 *
 * Adds the `ask_user` tool so the agent can pause and let the user choose
 * between a set of explicit options before continuing.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Static, Type } from "typebox";

const askUserSchema = Type.Object({
	question: Type.String({ description: "The question to ask the user" }),
	options: Type.Array(Type.String(), {
		description: "The choices the user can select from",
		minItems: 2,
	}),
});

export type AskUserInput = Static<typeof askUserSchema>;

export default function askUserExtension(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "ask_user",
		label: "Ask User",
		description: "Ask the user to choose one option before continuing.",
		promptSnippet: "Ask the user to choose between options",
		promptGuidelines: ["Use ask_user whenever multiple valid choices require the user's decision."],
		parameters: askUserSchema,
		executionMode: "sequential",

		async execute(_toolCallId, params: AskUserInput, _signal, _onUpdate, ctx) {
			if (!ctx.hasUI) {
				throw new Error("User selection requires interactive UI mode");
			}

			const choice = await ctx.ui.select(params.question, params.options);

			return {
				content: [
					{
						type: "text",
						text: choice
							? `The user chose: ${choice}`
							: "The user cancelled the selection.",
					},
				],
				details: { choice },
			};
		},
	});
}
