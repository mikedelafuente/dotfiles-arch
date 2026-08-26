-- ============================================================================
-- Claude Code Bridge (Neovim <-> Claude Code CLI)
-- ============================================================================
-- `provider = "none"`: the `code` command already launches `claude` in its own
-- tmux pane, so this plugin only runs the WebSocket/MCP server + lock-file
-- discovery (~/.claude/ide/*.lock) that the CLI auto-connects to by matching
-- cwd. It does not manage a terminal itself.
--
-- `lazy = false`: the server has to be up (and the lock file written) before
-- `claude` starts in the adjacent pane, or auto-discovery has nothing to find.
-- Lazy-loading on `cmd`/`keys` would only start it after the first
-- `:ClaudeCode*` command — too late for the `code` script's "both panes launch
-- together" flow. Run `/ide` inside the Claude pane as a manual fallback if a
-- session ever starts before Neovim finishes loading.

return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  lazy = false,
  opts = {
    terminal = {
      provider = "none",
    },
  },
  keys = {
    { "<leader>a", nil, desc = "Claude Code" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer to Claude" },
    {
      "<leader>as",
      "<cmd>ClaudeCodeTreeAdd<cr>",
      desc = "Add file to Claude",
      ft = { "NvimTree", "neo-tree", "oil", "minifiles", "netrw" },
    },
  },
  config = function(_, opts)
    require("claudecode").setup(opts)

    -- `focus_after_send` has no effect with provider = "none" (Claude runs
    -- outside Neovim). This is the documented workaround: jump tmux focus to
    -- the agent pane whenever a send is accepted. Matches the `code` command's
    -- fixed layout (nvim pane left, agent pane immediately to its right).
    vim.api.nvim_create_autocmd("User", {
      pattern = "ClaudeCodeSendComplete",
      callback = function()
        if vim.env.TMUX then
          vim.fn.system({ "tmux", "select-pane", "-R" })
        end
      end,
    })
  end,
}
