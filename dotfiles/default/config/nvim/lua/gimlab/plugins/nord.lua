return {
    "shaunsingh/nord.nvim",
    name = "nord",
    priority = 1000, -- load before all other plugins
    config = function()
        vim.cmd.colorscheme 'nord'
    end,
}
