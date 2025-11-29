-- ============================================================================
-- Lazy.nvim Plugin Manager Setup
-- ============================================================================
-- Bootstrap and configure lazy.nvim plugin manager

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load plugins from lua/plugins/ directory
require("lazy").setup("plugins", {
  defaults = {
    lazy = false,  -- Load plugins eagerly by default
  },
  install = {
    colorscheme = { "tokyonight", "habamax" },
  },
  checker = {
    enabled = true,   -- Automatically check for plugin updates
    notify = false,   -- Don't notify about updates
  },
  change_detection = {
    enabled = true,   -- Automatically reload plugins on change
    notify = false,   -- Don't notify about changes
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "matchit",
        "matchparen",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
