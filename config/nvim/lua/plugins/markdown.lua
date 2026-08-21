-- ============================================================================
-- Markdown rendering
-- ============================================================================
-- In-buffer Markdown preview via render-markdown.nvim (no Electron).
-- CLI alternative: `glow` / `md` from the shell.

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    ft = { "markdown" },
    opts = {},
    keys = {
      {
        "<leader>mr",
        "<cmd>RenderMarkdown toggle<cr>",
        desc = "Toggle markdown render",
        ft = "markdown",
      },
    },
  },
}
