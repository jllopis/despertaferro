return {
	'hrsh7th/nvim-cmp',
    event = "InsertEnter",
	dependencies = {
		{'hrsh7th/cmp-buffer'}, --- source for text in buffer
		{'hrsh7th/cmp-path'},   --- source for filesystem paths
		{'L3MON4D3/LuaSnip'}, --- snippet engine
		{'saadparwaiz1/cmp_luasnip'}, --- for autocompletion
		{'rafamadriz/friendly-snippets'}, --- useful snippets
	},
    config = function()
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        --- load vscode style snippets from installed plugins (e.g. friendly-snippets)
        require("luasnip.loaders.from_vscode").lazy_load()

        cmp.setup({
            completion = {
                completeopt = "menu,menuone,preview,noselect",
            },
            snippet = { --- configure how nvim-cmp interacts with the snippet engine
                expand = function(args)
                    luasnip.lsp_expand(args.body)
                end,
            },
            window = {
                completion = cmp.config.window.bordered(),
                documentation = cmp.config.window.bordered(),
            },
            mapping = cmp.mapping.preset.insert({
                -- `Enter` key to confirm completion
                ['<CR>'] = cmp.mapping.confirm({select = false}),

                -- Ctrl+Space to trigger completion menu
                ['<C-Space>'] = cmp.mapping.complete(),
                ['<ESC>'] = cmp.mapping.abort(),

                --- Navigate suggestions
                ['k'] = cmp.mapping.select_prev_item(),
                ['j'] = cmp.mapping.select_next_item(),
                ---['<C-k>'] = cmp.mapping.select_prev_item(),
                ---['<C-j>'] = cmp.mapping.select_next_item(),

                -- Scroll up and down in the completion documentation
                ['<C-b>'] = cmp.mapping.scroll_docs(-4),
                ['<C-f>'] = cmp.mapping.scroll_docs(4),
            }),
            --- sources for autocompletion
            sources = cmp.config.sources({
                { name = "nvim_lsp" }, --- language servers
                { name = "luasnip" }, --- snippets
                { name = "buffer" }, --- text within current buffer
                { name = "path" }, --- filesystem paths
            }),
        })
    end,
}

