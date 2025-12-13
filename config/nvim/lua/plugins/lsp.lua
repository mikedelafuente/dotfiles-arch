-- ============================================================================
-- LSP Configuration with Mason
-- ============================================================================
-- Language Server Protocol setup for multiple languages
--
-- This provides:
--   - Auto-completion
--   - Go to definition
--   - Hover documentation
--   - Code actions
--   - Diagnostics (errors/warnings)
-- ============================================================================

return {
    -- Mason: Portable package manager for LSP servers, DAP servers, linters, formatters
    {
        "williamboman/mason.nvim",
        config = function()
            require("mason").setup({
                ui = {
                    border = "rounded",
                    icons = {
                        package_installed = "✓",
                        package_pending = "➜",
                        package_uninstalled = "✗"
                    }
                }
            })
        end
    },

    -- Mason-lspconfig: Bridge between mason and lspconfig
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim" },
    },

    -- LSP Config: Quickstart configs for Neovim LSP
    {
        "neovim/nvim-lspconfig",
        event = {
            "BufReadPre",
            "BufNewFile" },
        dependencies = {
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "hrsh7th/cmp-nvim-lsp", -- LSP completion source
        },
        config = function()
            local lspconfig = require("lspconfig")
            local mason_lspconfig = require("mason-lspconfig")
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- First, setup mason-lspconfig
            mason_lspconfig.setup({
                -- Automatically install these LSP servers
                ensure_installed = {
                    "lua_ls",        -- Lua
                    "pyright",       -- Python
                    "ts_ls",         -- TypeScript/JavaScript
                    "rust_analyzer", -- Rust
                    "gopls",         -- Go
                    "bashls",        -- Bash
                    "intelephense",  -- PHP
                    "psalm",         -- PHP static analysis
                    -- Note: omnisharp (C#) needs to be installed manually via Mason
                },
                automatic_installation = true,
            })

            -- Diagnostic configuration
            vim.diagnostic.config({
                virtual_text = true,
                signs = true,
                update_in_insert = false,
                underline = true,
                severity_sort = true,
                float = {
                    border = "rounded",
                    source = "always",
                },
            })

            -- Diagnostic signs
            local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
            for type, icon in pairs(signs) do
                local hl = "DiagnosticSign" .. type
                vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
            end

            -- LSP keybindings (applied when LSP attaches to buffer)
            local on_attach = function(client, bufnr)
                local opts = { buffer = bufnr, noremap = true, silent = true }

                -- Navigation
                vim.keymap.set("n", "gd", vim.lsp.buf.definition,
                    vim.tbl_extend("force", opts, { desc = "Go to definition" }))
                vim.keymap.set("n", "gD", vim.lsp.buf.declaration,
                    vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
                vim.keymap.set("n", "gi", vim.lsp.buf.implementation,
                    vim.tbl_extend("force", opts, { desc = "Go to implementation" }))
                vim.keymap.set("n", "gr", vim.lsp.buf.references,
                    vim.tbl_extend("force", opts, { desc = "Go to references" }))
                vim.keymap.set("n", "K", vim.lsp.buf.hover,
                    vim.tbl_extend("force", opts, { desc = "Show hover documentation" }))

                -- Actions
                vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action,
                    vim.tbl_extend("force", opts, { desc = "Code actions" }))
                vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename,
                    vim.tbl_extend("force", opts, { desc = "Rename symbol" }))
                vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format({ async = true }) end,
                    vim.tbl_extend("force", opts, { desc = "Format document" }))

                -- Diagnostics
                vim.keymap.set("n", "[d", vim.diagnostic.goto_prev,
                    vim.tbl_extend("force", opts, { desc = "Previous diagnostic" }))
                vim.keymap.set("n", "]d", vim.diagnostic.goto_next,
                    vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
                vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float,
                    vim.tbl_extend("force", opts, { desc = "Show diagnostic" }))
                vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist,
                    vim.tbl_extend("force", opts, { desc = "Diagnostic list" }))
            end

            -- Server configurations
            local servers = {
                lua_ls = {
                    settings = {
                        Lua = {
                            diagnostics = {
                                globals = { "vim" }, -- Recognize 'vim' global
                            },
                            workspace = {
                                library = vim.api.nvim_get_runtime_file("", true),
                                checkThirdParty = false,
                            },
                            telemetry = { enable = false },
                        },
                    },
                },
                pyright = {},
                ts_ls = {},
                rust_analyzer = {
                    settings = {
                        ["rust-analyzer"] = {
                            checkOnSave = {
                                command = "clippy",
                            },
                        },
                    },
                },
                gopls = {},
                bashls = {},
                intelephense = {
                    settings = {
                        intelephense = {
                            diagnostics = {
                                enable = true,
                                undefinedSymbols = true,
                                undefinedVariables = true,
                                undefinedMethods = true,
                                undefinedClassConstants = true,
                                undefinedFunctions = true,
                                undefinedTypes = true,
                                undefinedConstants = true,
                                argumentCount = true,
                            },
                        },
                    },
                },
                psalm = {
                    settings = {
                        psalm = {
                            enableCodeActions = true,
                            hoistAnalysis = false,
                            symbolsToIgnore = {},
                            hideInlayHints = {},
                        },
                    },
                },
            }

            -- Setup all servers using vim.lsp.config (Neovim 0.11+)
            for server_name, config in pairs(servers) do
                local server_config = vim.tbl_extend("force", {
                    capabilities = capabilities,
                    on_attach = on_attach,
                }, config)

                -- Use vim.lsp.config for Neovim 0.11+
                vim.lsp.config[server_name] = server_config
            end

            -- Auto-start LSP servers for configured filetypes
            vim.api.nvim_create_autocmd("FileType", {
                callback = function(args)
                    -- Map filetypes to LSP servers (can be string or table of strings for multiple servers)
                    local filetype_servers = {
                        lua = "lua_ls",
                        python = "pyright",
                        javascript = "ts_ls",
                        typescript = "ts_ls",
                        javascriptreact = "ts_ls",
                        typescriptreact = "ts_ls",
                        rust = "rust_analyzer",
                        go = "gopls",
                        sh = "bashls",
                        bash = "bashls",
                        php = { "intelephense", "psalm" },
                    }

                    local server_list = filetype_servers[args.match]
                    if not server_list then return end

                    -- Handle both single server string and multiple servers table
                    if type(server_list) == "string" then
                        server_list = { server_list }
                    end

                    -- Enable all configured servers for this filetype
                    for _, server in ipairs(server_list) do
                        if servers[server] then
                            vim.lsp.enable(server)
                        end
                    end
                end,
            })
        end
    },
}
