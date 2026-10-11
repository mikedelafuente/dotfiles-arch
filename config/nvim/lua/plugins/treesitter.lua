-- ============================================================================
-- Treesitter Configuration
-- ============================================================================
-- Supports both nvim-treesitter `main` (Neovim 0.12+) and legacy `master` checkouts.
-- Use upstream's frozen master compatibility branch with Ubuntu's Neovim 0.11.
local modern = vim.fn.has("nvim-0.12") == 1

local parsers = {
  "bash",
  "c",
  "c_sharp",
  "css",
  "dockerfile",
  "go",
  "html",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "php",
  "python",
  "rust",
  "toml",
  "typescript",
  "vim",
  "yaml",
}

local function setup_main()
  local ts = require("nvim-treesitter")
  ts.setup({
    install_dir = vim.fn.stdpath("data") .. "/site",
  })

  -- Async install; no-op when already present
  pcall(function()
    ts.install(parsers)
  end)

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("DotfilesTreesitter", { clear = true }),
    callback = function(args)
      local buf = args.buf
      pcall(vim.treesitter.start, buf)
      pcall(function()
        vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end)
    end,
  })
end

local function setup_legacy()
  require("nvim-treesitter.configs").setup({
    ensure_installed = parsers,
    sync_install = false,
    auto_install = true,
    highlight = { enable = true },
    indent = { enable = true },
    textobjects = {
      select = {
        enable = true,
        lookahead = true,
        keymaps = {
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
          ["ac"] = "@class.outer",
          ["ic"] = "@class.inner",
        },
      },
    },
  })
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = modern and "main" or "master",
    commit = not modern and "cf12346a3414fa1b06af75c79faebe7f76df080a" or nil,
    lazy = false,
    build = ":TSUpdate",
    config = function()
      if not modern then
        setup_legacy()
        return
      end
      local ok, ts = pcall(require, "nvim-treesitter")
      if ok and type(ts.install) == "function" then
        setup_main()
      else
        -- Installed checkout is still legacy master; avoid crashing on startup.
        vim.notify(
          "nvim-treesitter is on legacy master; run :Lazy sync to switch to main",
          vim.log.levels.WARN
        )
        pcall(setup_legacy)
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = modern and "main" or "master",
    commit = not modern and "5ca4aaa6efdcc59be46b95a3e876300cfead05ef" or nil,
    lazy = false,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      local ok, textobjects = pcall(require, "nvim-treesitter-textobjects")
      if not ok or type(textobjects.setup) ~= "function" then
        -- Legacy textobjects are configured via nvim-treesitter.configs above.
        return
      end

      textobjects.setup({
        select = {
          lookahead = true,
          selection_modes = {
            ["@parameter.outer"] = "v",
            ["@function.outer"] = "V",
            ["@class.outer"] = "V",
          },
          include_surrounding_whitespace = false,
        },
      })

      local select_ok, select = pcall(require, "nvim-treesitter-textobjects.select")
      if not select_ok then
        return
      end

      vim.keymap.set({ "x", "o" }, "af", function()
        select.select_textobject("@function.outer", "textobjects")
      end, { desc = "Select around function" })
      vim.keymap.set({ "x", "o" }, "if", function()
        select.select_textobject("@function.inner", "textobjects")
      end, { desc = "Select inside function" })
      vim.keymap.set({ "x", "o" }, "ac", function()
        select.select_textobject("@class.outer", "textobjects")
      end, { desc = "Select around class" })
      vim.keymap.set({ "x", "o" }, "ic", function()
        select.select_textobject("@class.inner", "textobjects")
      end, { desc = "Select inside class" })
    end,
  },
}
