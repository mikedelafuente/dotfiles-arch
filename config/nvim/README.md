# Neovim Configuration

A clean, beginner-friendly Neovim setup with LSP support for multiple programming languages, modern plugins, and intuitive keybindings.

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Plugins](#-plugins)
- [Keybindings](#-keybindings)
- [LSP Servers](#-lsp-servers)
- [File Structure](#-file-structure)
- [Customization](#-customization)
- [Troubleshooting](#-troubleshooting)

## ✨ Features

- 🎯 **LSP Support** - Intelligent code completion, go-to-definition, diagnostics for 8+ languages
- 🌳 **Treesitter** - Advanced syntax highlighting and code understanding
- 🔍 **Telescope** - Fuzzy finder for files, text, buffers, and more
- 📦 **Mason** - Easy LSP server, linter, and formatter management
- 💡 **Auto-completion** - Smart completion with snippets
- 🗺️ **Which-key** - Discover keybindings as you type (perfect for beginners!)
- 📁 **File Explorer** - nvim-tree for intuitive file navigation
- 🎨 **Modern UI** - Tokyo Night theme, lualine statusline, indent guides, git integration
- ⌨️ **Beginner-friendly** - Well-documented keybindings and clear configuration

## 📦 Prerequisites

These are automatically installed by `setup-neovim.sh`:

- Neovim >= 0.10.0
- Git
- A C compiler (gcc/clang)
- Node.js (for LSP servers)
- Python 3 with pip
- ripgrep (for Telescope live grep)
- fd (for Telescope find files)

## 🚀 Installation

The configuration is managed through the dotfiles repository:

```bash
# Run the setup script
bash ~/repos/dotfiles-fedora/scripts/setup-neovim.sh

# Link the configuration files
bash ~/repos/dotfiles-fedora/scripts/link-dotfiles.sh

# Start Neovim (plugins will install automatically)
nvim
```

On first launch:
1. Lazy.nvim will install all plugins automatically
2. Treesitter will install language parsers
3. Mason will install LSP servers

## 🔌 Plugins

### Core Functionality

| Plugin | Purpose | Commands |
|--------|---------|----------|
| **lazy.nvim** | Plugin manager | `:Lazy` |
| **mason.nvim** | LSP/tool installer | `:Mason` |
| **nvim-lspconfig** | LSP configuration | `:LspInfo` |
| **nvim-cmp** | Autocompletion | - |
| **LuaSnip** | Snippet engine | - |

### Navigation & Search

| Plugin | Purpose | Keybindings |
|--------|---------|-------------|
| **telescope.nvim** | Fuzzy finder | `<leader>ff`, `<leader>fg`, `<leader>fb` |
| **nvim-tree** | File explorer | `<leader>e` |
| **which-key.nvim** | Keybinding helper | Automatic popup |

### Code Understanding

| Plugin | Purpose | Features |
|--------|---------|----------|
| **nvim-treesitter** | Syntax highlighting | Better highlighting, text objects |
| **treesitter-textobjects** | Smart text selection | `af`, `if`, `ac`, `ic` |

### UI Enhancements

| Plugin | Purpose | Visual Impact |
|--------|---------|---------------|
| **tokyonight.nvim** | Color scheme | Dark, modern theme |
| **lualine.nvim** | Statusline | Git branch, diagnostics, file info |
| **indent-blankline** | Indent guides | Visual indentation levels |
| **gitsigns.nvim** | Git integration | Line changes, blame, hunk navigation |
| **nvim-web-devicons** | File icons | Icons throughout UI |
| **dressing.nvim** | Better UI inputs | Improved select/input |

## ⌨️ Keybindings

**Leader key: `<Space>`** (press space to see all available commands via which-key)

### General Navigation

| Key | Action | Mode |
|-----|--------|------|
| `<Esc>` | Clear search highlighting | Normal |
| `<C-h/j/k/l>` | Navigate between windows | Normal |
| `<C-Up/Down/Left/Right>` | Resize windows | Normal |
| `<S-h>` / `<S-l>` | Previous/Next buffer | Normal |
| `<leader>bd` | Delete buffer | Normal |
| `<C-s>` | Save file | Normal |

### File Navigation (Telescope)

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>ff` | Find files | Fuzzy find files in project |
| `<leader>fg` | Live grep | Search text in all files |
| `<leader>fb` | Find buffers | List open buffers |
| `<leader>fh` | Help tags | Search Neovim help |
| `<leader>fr` | Recent files | Recently opened files |
| `<leader>fc` | Find word under cursor | Search current word |
| `<leader>fk` | Find keymaps | List all keymaps |

### File Explorer

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>e` | Toggle file explorer | Open/close nvim-tree |

**Inside nvim-tree:**
- `<CR>` - Open file
- `o` - Open file/folder
- `a` - Create file
- `d` - Delete file
- `r` - Rename file
- `x` - Cut file
- `c` - Copy file
- `p` - Paste file
- `R` - Refresh tree
- `?` - Show help

### LSP (Language Server)

| Key | Action | Description |
|-----|--------|-------------|
| `gd` | Go to definition | Jump to where symbol is defined |
| `gD` | Go to declaration | Jump to symbol declaration |
| `gi` | Go to implementation | Jump to implementation |
| `gr` | Go to references | Show all references |
| `K` | Hover documentation | Show documentation for symbol under cursor |
| `<leader>ca` | Code actions | Show available code actions |
| `<leader>rn` | Rename symbol | Rename symbol across project |
| `<leader>f` | Format document | Format current file |
| `[d` | Previous diagnostic | Go to previous error/warning |
| `]d` | Next diagnostic | Go to next error/warning |
| `<leader>d` | Show diagnostic | Show error/warning details |
| `<leader>q` | Diagnostic list | Open diagnostic quickfix list |

### Completion (Insert Mode)

| Key | Action |
|-----|--------|
| `<C-Space>` | Trigger completion |
| `<CR>` | Confirm selection |
| `<Tab>` | Next item / expand snippet |
| `<S-Tab>` | Previous item / previous snippet placeholder |
| `<C-b>` | Scroll docs up |
| `<C-f>` | Scroll docs down |
| `<C-e>` | Abort completion |

### Git (Gitsigns)

| Key | Action | Description |
|-----|--------|-------------|
| `]c` | Next hunk | Go to next git change |
| `[c` | Previous hunk | Go to previous git change |
| `<leader>gs` | Stage hunk | Stage current change |
| `<leader>gr` | Reset hunk | Discard current change |
| `<leader>gp` | Preview hunk | Preview git change |
| `<leader>gb` | Blame line | Show git blame |

### Code Editing

| Key | Action | Mode |
|-----|--------|------|
| `<` / `>` | Indent left/right (stays in visual mode) | Visual |
| `<A-j>` / `<A-k>` | Move line down/up | Normal/Visual |
| `<C-Space>` | Incremental selection | Normal |

### Treesitter Text Objects

| Key | Action | Mode |
|-----|--------|------|
| `af` | Select around function | Visual |
| `if` | Select inside function | Visual |
| `ac` | Select around class | Visual |
| `ic` | Select inside class | Visual |

## 🔧 LSP Servers

The following LSP servers are automatically installed via Mason:

| Language | Server | Auto-installed |
|----------|--------|----------------|
| Lua | `lua_ls` | ✅ |
| Python | `pyright` | ✅ |
| JavaScript/TypeScript | `ts_ls` | ✅ |
| Rust | `rust_analyzer` | ✅ |
| Go | `gopls` | ✅ |
| Bash | `bashls` | ✅ |
| PHP | `intelephense` | ✅ |
| C# | `omnisharp` | ⚠️ Manual via `:Mason` |

### Installing Additional LSP Servers

```vim
:Mason
```

Use:
- `i` to install
- `u` to update
- `X` to uninstall

## 📁 File Structure

```
~/.config/nvim/
├── init.lua                    # Entry point
├── lua/
│   ├── config/
│   │   ├── options.lua         # Vim options (tabs, numbers, etc.)
│   │   ├── keymaps.lua         # General keybindings
│   │   └── lazy.lua            # Plugin manager setup
│   └── plugins/
│       ├── lsp.lua             # LSP configuration
│       ├── cmp.lua             # Autocompletion
│       ├── treesitter.lua      # Syntax highlighting
│       ├── telescope.lua       # Fuzzy finder
│       ├── which-key.lua       # Keybinding discovery
│       └── ui.lua              # UI plugins (theme, statusline, etc.)
```

## 🎨 Customization

### Changing the Color Scheme

Edit `lua/plugins/ui.lua`:

```lua
-- Replace tokyonight with another theme
{
  "catppuccin/nvim",  -- or "folke/tokyonight.nvim", "rebelot/kanagawa.nvim", etc.
  name = "catppuccin",
  config = function()
    vim.cmd([[colorscheme catppuccin]])
  end,
}
```

### Adding a New LSP Server

1. Open Mason: `:Mason`
2. Find and install your server
3. Add to `lua/plugins/lsp.lua`:

```lua
local servers = {
  -- ... existing servers ...
  your_server = {
    -- Optional server-specific settings
  },
}
```

### Changing Leader Key

Edit `lua/config/options.lua`:

```lua
vim.g.mapleader = ","  -- Change from Space to comma
```

### Adding Custom Keybindings

Edit `lua/config/keymaps.lua`:

```lua
vim.keymap.set("n", "<leader>x", "<cmd>YourCommand<cr>", { desc = "Your description" })
```

## 🐛 Troubleshooting

### Check Neovim Health

```vim
:checkhealth
```

### LSP Not Working

1. Check if LSP server is installed: `:Mason`
2. Check LSP status: `:LspInfo`
3. Check health: `:checkhealth lsp`

### Treesitter Highlighting Issues

```vim
:TSUpdate         " Update all parsers
:TSInstall <lang> " Install specific parser
```

### Plugin Issues

```vim
:Lazy             " Open plugin manager
:Lazy sync        " Update all plugins
:Lazy clean       " Remove unused plugins
```

### Starting Fresh

```bash
# Backup and remove Neovim data
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim

# Restart Neovim (plugins will reinstall)
nvim
```

## 📚 Learning Resources

- Press `<Space>` to see available commands (which-key)
- `:help <topic>` for Neovim help (e.g., `:help lsp`)
- `:Tutor` for Vim basics
- [Neovim Documentation](https://neovim.io/doc/)
- [LSP Config Documentation](https://github.com/neovim/nvim-lspconfig)

## 🔄 Updating

```bash
# Update dotfiles repository
cd ~/repos/dotfiles-fedora
git pull

# Relink configuration (if needed)
bash scripts/link-dotfiles.sh

# Update plugins in Neovim
nvim +Lazy sync
```

---

**Maintained as part of the dotfiles-fedora repository**
