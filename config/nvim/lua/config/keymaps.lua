-- ============================================================================
-- Key Mappings Configuration
-- ============================================================================
-- Beginner-friendly key bindings with clear comments

local keymap = vim.keymap.set

-- ============================================================================
-- General Mappings
-- ============================================================================

-- Clear search highlighting with <Esc>
keymap("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlighting" })

-- Better window navigation
keymap("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Move to bottom window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Move to top window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Resize windows with arrows
keymap("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Increase window height" })
keymap("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Decrease window height" })
keymap("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
keymap("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- Buffer navigation
keymap("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- Better indenting (stay in visual mode)
keymap("v", "<", "<gv", { desc = "Indent left" })
keymap("v", ">", ">gv", { desc = "Indent right" })

-- Move lines up and down
keymap("n", "<A-j>", "<cmd>m .+1<CR>==", { desc = "Move line down" })
keymap("n", "<A-k>", "<cmd>m .-2<CR>==", { desc = "Move line up" })
keymap("v", "<A-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
keymap("v", "<A-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Save file
keymap("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })

-- Format document with LSP
keymap("n", "<leader>lf", "<cmd>lua vim.lsp.buf.format()<CR>", { desc = "Format document" })

-- ============================================================================
-- Plugin-specific Mappings (defined here for reference)
-- ============================================================================
-- Most plugin mappings are defined in their respective plugin config files
-- See lua/plugins/*.lua for:
--   - <leader>ff, fg, fb (Telescope)
--   - <leader>e (File Explorer)
--   - gd, gr, K, <leader>ca, <leader>rn (LSP)
--   - <leader>? (Which-key help)
