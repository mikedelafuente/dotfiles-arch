-- ============================================================================
-- GitHub Copilot Configuration
-- ============================================================================
-- AI-powered code completion from GitHub Copilot
--
-- Setup:
--   1. Run :Copilot setup in Neovim
--   2. Follow authentication instructions
--   3. Requires active GitHub Copilot subscription
-- ============================================================================

return {
  "github/copilot.vim",
  event = "InsertEnter",
  config = function()
    -- Copilot keybindings are set by default:
    -- Tab to accept suggestion (in insert mode)
    -- Alt+] to next suggestion
    -- Alt+[ to previous suggestion
    -- Alt+\ to dismiss suggestion
    
    -- Optional: Disable Copilot for specific filetypes
    vim.g.copilot_filetypes = {
      ["*"] = true,
      -- gitcommit = false,
      -- markdown = false,
    }
    
    -- Optional: Set node path if needed
    -- vim.g.copilot_node_command = "/usr/bin/node"
  end,
}
