-- ============================================================================
-- Vim Options Configuration
-- ============================================================================
-- Sensible defaults for a modern development environment

local opt = vim.opt

-- Line Numbers
opt.number = true           -- Show line numbers
opt.relativenumber = true   -- Show relative line numbers
opt.signcolumn = "yes"      -- Always show sign column (for git, diagnostics)

-- Tabs & Indentation
opt.tabstop = 4             -- 4 spaces for tabs
opt.shiftwidth = 4          -- 4 spaces for indent width
opt.expandtab = true        -- Use spaces instead of tabs
opt.autoindent = true       -- Copy indent from current line
opt.smartindent = true      -- Smart indenting for programming

-- Line Wrapping
opt.wrap = false            -- Disable line wrapping

-- Search Settings
opt.ignorecase = true       -- Ignore case when searching
opt.smartcase = true        -- Override ignorecase if search contains capitals
opt.hlsearch = true         -- Highlight all search matches
opt.incsearch = true        -- Show matches as you type

-- Appearance
opt.termguicolors = true    -- True color support
opt.background = "dark"     -- Dark background
opt.cursorline = true       -- Highlight current line
opt.scrolloff = 8           -- Keep 8 lines above/below cursor
opt.sidescrolloff = 8       -- Keep 8 columns left/right of cursor

-- Behavior
opt.mouse = "a"             -- Enable mouse support
opt.clipboard = "unnamedplus" -- Use system clipboard
opt.undofile = true         -- Save undo history
opt.swapfile = false        -- Disable swap files
opt.backup = false          -- Disable backup files
opt.updatetime = 250        -- Faster completion (4000ms default)
opt.timeoutlen = 300        -- Time to wait for mapped sequence (ms)

-- Split Windows
opt.splitright = true       -- Vertical split to the right
opt.splitbelow = true       -- Horizontal split to the bottom

-- File Encoding
opt.fileencoding = "utf-8"  -- UTF-8 encoding

-- Completion
opt.completeopt = "menu,menuone,noselect"  -- Completion options

-- Set leader key (must be set before plugins load)
vim.g.mapleader = " "       -- Space as leader key
vim.g.maplocalleader = " "
