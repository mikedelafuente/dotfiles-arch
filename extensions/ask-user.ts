import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "ask_user",
    label: "Ask User",
    description: "Ask the user to choose one option before continuing.",
    promptSnippet: "Ask the user to choose between options",
    promptGuidelines: [
      "Use ask_user whenever multiple valid choices require the user's decision.",
    ],
    parameters: Type.Object({
      question: Type.String({ description: "The question to ask the user" }),
      options: Type.Array(Type.String(), {
        description: "The choices the user can select from",
        minItems: 2,
      }),
    }),
    executionMode: "sequential",

    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      if (ctx.mode !== "tui") {
        throw new Error("User selection requires interactive TUI mode");
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
