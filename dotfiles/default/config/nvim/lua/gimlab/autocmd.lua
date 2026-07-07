-- source: https://haddock.crabdance.com/code/weeheavy/neovim/src/commit/b248c5a7b37545265fc43002d2d2afd568b27fce/lua/weeheavy/autocmd.lua
-- Native autocompletion
vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("my.lsp", {}),
    callback = function(args)
        local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
        if client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = false })
        end
        -- Auto-format ("lint") on save.
        -- Usually not needed if server supports "textDocument/willSaveWaitUntil".
        if
            not client:supports_method("textDocument/willSaveWaitUntil")
            and client:supports_method("textDocument/formatting")
        then
            vim.api.nvim_create_autocmd("BufWritePre", {
                group = vim.api.nvim_create_augroup("my.lsp", { clear = false }),
                buffer = args.buf,
                callback = function()
                    vim.lsp.buf.format({ bufnr = args.buf, id = client.id, timeout_ms = 1000 })
                end,
            })
        end
    end,
})

-- Highlight yanked text on e.g. yy,yap etc.
vim.api.nvim_create_autocmd("TextYankPost", {
    desc = "Highlight when yanking (copying) text",
    group = vim.api.nvim_create_augroup("weeheavy-highlight-yank", { clear = true }),
    callback = function()
        vim.highlight.on_yank({
            higroup = "IncSearch",
            timeout = 100,
        })
    end,
})

-- Habilitar zls para archivos Zig
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'zig',
  callback = function()
    vim.lsp.enable('zls')
  end,
})

-- https://github.com/LazyVim/LazyVim/discussions/654
vim.api.nvim_create_autocmd("FileType", {
    pattern = "terraform",
    callback = function()
        vim.bo.commentstring = "# %s"
    end,
})

-- Force correct filetype for Docker compose files
local ft_lsp_group = vim.api.nvim_create_augroup("ft_lsp_group", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    pattern = { "docker_compose.yml", "docker_compose_*.yml" },
    group = ft_lsp_group,
    desc = "Force docker-compose ft",
    callback = function()
        vim.opt.filetype = "yaml.docker-compose"
    end,
})

