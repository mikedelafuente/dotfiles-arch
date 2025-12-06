return {
  "jiaoshijie/undotree",
  -- Load the plugin only when its keybinding is used
  keys = {
    { "<leader>u", "<cmd>lua require('undotree').toggle()<cr>", desc = "Toggle Undotree" },
  },
  config = function()
    require("undotree").setup({
      -- Your configuration options here (optional)
      float_diff = true, -- use a floating window for diff previews
      layout = "left_bottom", -- position the undotree window
      position = "left",
      window = {
        winblend = 30,
        border = "rounded",
      },
    })
  end,
}

