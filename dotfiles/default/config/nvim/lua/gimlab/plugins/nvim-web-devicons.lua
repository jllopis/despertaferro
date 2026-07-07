return {
    "nvim-tree/nvim-web-devicons",
    config = function()
        local nwd = require("nvim-web-devicons")
        nwd.setup {
            strict = true,
            color_icons = true,
            -- globally enable default icons (default to false)
            -- will get overriden by `get_icons` option
            default = true,
            override = {
                zsh = {
                    icon = "",
                    color = "#428850",
                    cterm_color = "65",
                    name = "Zsh"
                },
                gql = {
                    icon = "",
                    color = "#e535ab",
                    cterm_color = "199",
                    name = "GraphQL"
                },
            },
            override_by_filename = {
                [".gitignore"] = {
                    icon = "",
                    color = "#f1502f",
                    name = "Gitignore"
                }
            },
        }
    end,
}
