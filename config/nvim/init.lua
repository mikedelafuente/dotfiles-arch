-- ============================================================================-- bootstrap lazy.nvim, LazyVim and your plugins

-- Neovim Configurationrequire("config.lazy")
-- ============================================================================
-- A clean, beginner-friendly Neovim setup with LSP support for multiple languages
--
-- Quick Start Guide:
--   <Space> is the leader key - press it to see available commands
--   :Mason - Open Mason to install/manage LSP servers
--   :Lazy - Open Lazy.nvim plugin manager
--   :checkhealth - Verify your Neovim installation
--
-- File Navigation:
--   <Space>ff - Find files
--   <Space>fg - Live grep (search in files)
--   <Space>fb - Find buffers
--   <Space>e  - Toggle file explorer
--
-- LSP Commands:
--   gd - Go to definition
--   gr - Go to references
--   K - Show hover documentation
--   <Space>ca - Code actions
--   <Space>rn - Rename symbol
-- ============================================================================

-- Load configuration modules
require("config.options")   -- Vim options (line numbers, tabs, etc.)
require("config.lazy")      -- Plugin manager setup
require("config.keymaps")   -- Key mappings (loaded after plugins)
