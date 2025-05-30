local utils = require("utils")

local mason = require("mason")
local mason_lspconfig = require("mason-lspconfig")
local lspconfig = require("lspconfig")

mason.setup()

local lsp_config = {
  ensure_installed = { "bashls", "clangd", "cmake", "cssls", "tailwindcss", "dockerls", "ts_ls" },
  handlers = {
    function(server_name)
      if server_name == "ts_ls" then
        lspconfig.ts_ls.setup {
          settings = {
            parser_install_directories = {
              -- If using nvim-treesitter with lazy.nvim
              vim.fs.joinpath(
                vim.fn.stdpath('data'),
                '/lazy/nvim-treesitter/parser/'
              ),
            },
            -- This setting is provided by default
            parser_aliases = {
              ecma = 'javascript',
              jsx = 'javascript',
            },
            -- E.g. zed support
            language_retrieval_patterns = {
              'languages/src/([^/]+)/[^/]+\\.scm$',
            },
          },
        }
      end
    end,
  }
}

mason_lspconfig.setup(lsp_config)

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("buf_behavior_conf", { clear = true }),
  callback = function(event_context)
    local client = vim.lsp.get_client_by_id(event_context.data.client_id)
    -- vim.print(client.name, client.server_capabilities)

    if not client then
      return
    end

    local bufnr = event_context.buf

    -- Mappings.
    local map = function(mode, l, r, opts)
      opts = opts or {}
      opts.silent = true
      opts.buffer = bufnr
      vim.keymap.set(mode, l, r, opts)
    end

    map("n", "gd", vim.lsp.buf.definition, { desc = "go to definition" })
    map("n", "<C-]>", vim.lsp.buf.definition)
    map("n", "K", function()
      vim.lsp.buf.hover { border = "single", max_height = 25, max_width = 120 }
    end)
    map("n", "<C-k>", vim.lsp.buf.signature_help)
    map("n", "<space>rn", vim.lsp.buf.rename, { desc = "varialbe rename" })
    map("n", "<space>ca", vim.lsp.buf.code_action, { desc = "LSP code action" })
    map("n", "<space>wa", vim.lsp.buf.add_workspace_folder, { desc = "add workspace folder" })
    map("n", "<space>wr", vim.lsp.buf.remove_workspace_folder, { desc = "remove workspace folder" })
    map("n", "<space>wl", function()
      vim.print(vim.lsp.buf.list_workspace_folders())
    end, { desc = "list workspace folder" })

    -- Set some key bindings conditional on server capabilities
    if client.server_capabilities.documentFormattingProvider and client.name ~= "lua_ls" then
      map({ "n", "x" }, "<space>f", vim.lsp.buf.format, { desc = "format code" })
    end

    -- Disable ruff hover feature in favor of Pyright
    if client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end

    -- Uncomment code below to enable inlay hint from language server, some LSP server supports inlay hint,
    -- but disable this feature by default, so you may need to enable inlay hint in the LSP server config.
    -- vim.lsp.inlay_hint.enable(true, {buffer=bufnr})

    -- The blow command will highlight the current variable and its usages in the buffer.
    if client.server_capabilities.documentHighlightProvider then
      local gid = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = true })
      vim.api.nvim_create_autocmd("CursorHold", {
        group = gid,
        buffer = bufnr,
        callback = function()
          vim.lsp.buf.document_highlight()
        end,
      })

      vim.api.nvim_create_autocmd("CursorMoved", {
        group = gid,
        buffer = bufnr,
        callback = function()
          vim.lsp.buf.clear_references()
        end,
      })
    end
  end,
  nested = true,
  desc = "Configure buffer keymap and behavior based on LSP",
})

local capabilities = vim.lsp.protocol.make_client_capabilities()

-- required by nvim-ufo
capabilities.textDocument.foldingRange = {
  dynamicRegistration = false,
  lineFoldingOnly = true,
}

-- For what diagnostic is enabled in which type checking mode, check doc:
-- https://github.com/microsoft/pyright/blob/main/docs/configuration.md#diagnostic-settings-defaults
-- Currently, the pyright also has some issues displaying hover documentation:
-- https://www.reddit.com/r/neovim/comments/1gdv1rc/what_is_causeing_the_lsp_hover_docs_to_looks_like/

if utils.executable("pyright") then
  local new_capability = {
    -- this will remove some of the diagnostics that duplicates those from ruff, idea taken and adapted from
    -- here: https://github.com/astral-sh/ruff-lsp/issues/384#issuecomment-1989619482
    textDocument = {
      publishDiagnostics = {
        tagSupport = {
          valueSet = { 2 },
        },
      },
      hover = {
        contentFormat = { "plaintext" },
        dynamicRegistration = true,
      },
    },
  }
  local merged_capability = vim.tbl_deep_extend("force", capabilities, new_capability)

  vim.lsp.config("pyright", {
    cmd = { "delance-langserver", "--stdio" },
    capabilities = merged_capability,
    settings = {
      pyright = {
        -- disable import sorting and use Ruff for this
        disableOrganizeImports = true,
        disableTaggedHints = false,
      },
      python = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          typeCheckingMode = "standard",
          useLibraryCodeForTypes = true,
          -- we can this setting below to redefine some diagnostics
          diagnosticSeverityOverrides = {
            deprecateTypingAliases = false,
          },
          -- inlay hint settings are provided by pylance?
          inlayHints = {
            callArgumentNames = "partial",
            functionReturnTypes = true,
            pytestParameters = true,
            variableTypes = true,
          },
        },
      },
    },
  })

  vim.lsp.enable("pyright")
else
  vim.notify("pyright not found!", vim.log.levels.WARN, { title = "Nvim-config" })
end

if utils.executable("ruff") then
  vim.lsp.config("ruff", {
    capabilities = capabilities,
    init_options = {
      -- the settings can be found here: https://docs.astral.sh/ruff/editors/settings/
      settings = {
        organizeImports = true,
      },
    },
  })
  vim.lsp.enable("ruff")
end

if utils.executable("ltex-ls") then
  vim.lsp.config("ltex", {
    filetypes = { "text", "plaintex", "tex", "markdown" },
    settings = {
      ltex = {
        language = "en",
      },
    },
    flags = { debounce_text_changes = 300 },
  })

  vim.lsp.enable("ltex")
end

if utils.executable("clangd") then
  vim.lsp.config("clangd", {
    capabilities = capabilities,
    filetypes = { "c", "cpp", "cc" },
    flags = {
      debounce_text_changes = 500,
    },
  })

  vim.lsp.enable("clangd")
end

-- set up vim-language-server
if utils.executable("vim-language-server") then
  vim.lsp.config("vimls", {
    flags = {
      debounce_text_changes = 500,
    },
    capabilities = capabilities,
  })

  vim.lsp.enable("vimls")
else
  vim.notify("vim-language-server not found!", vim.log.levels.WARN, { title = "Nvim-config" })
end

-- set up bash-language-server
if utils.executable("bash-language-server") then
  vim.lsp.config("bashls", {
    capabilities = capabilities,
  })

  vim.lsp.enable("bashls")
end

-- settings for lua-language-server can be found on https://luals.github.io/wiki/settings/
if utils.executable("lua-language-server") then
  vim.lsp.config("lua_ls", {
    settings = {
      Lua = {
        runtime = {
          -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
          version = "LuaJIT",
        },
        hint = {
          enable = true,
        },
      },
    },
    capabilities = capabilities,
  })

  vim.lsp.enable("lua_ls")
end
