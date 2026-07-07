return {
"akinsho/bufferline.nvim",
dependencies = { "nvim-tree/nvim-web-devicons" },
version = "*",
opts = {
    options = {
        mode = "buffers",
        numbers = function(opts)
            return string.format('%s·%s', opts.raise(opts.id), opts.lower(opts.ordinal))
        end,
        indicator = {
                icon = '▎', -- this should be omitted if indicator style is not 'icon'
                style = 'icon',
            },
            buffer_close_icon = '󰅖',
            modified_icon = '●',
            close_icon = '',
            left_trunc_marker = '',
            right_trunc_marker = '',
            diagnostics = "nvim_lsp",
            diagnostics_indicator = function(count, level, diagnostics_dict, context)
                local s = " "
                for e, n in pairs(diagnostics_dict) do
                    local sym = e == "error" and " "
                    or (e == "warning" and " " or "" )
                    s = s .. n .. sym
                end
                return s
            end,
            hover = {
                enabled = false,
                delay = 200,
                reveal = {'close'}
            },
---			mode = "tabs",
---			separator_style = "slant",
		},
	},
}
