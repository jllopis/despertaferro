return {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    keys = {
        { "<leader>Rs", function() require("kulala").run() end, mode = { "n", "v" }, desc = "Send request" },
        { "<leader>Ra", function() require("kulala").run_all() end, mode = { "n", "v" }, desc = "Send all requests" },
        { "<leader>Rr", function() require("kulala").replay() end, desc = "Replay last request" },
        { "<leader>Rb", function() require("kulala").scratchpad() end, desc = "Open scratchpad" },
        { "<leader>Ro", function() require("kulala").open() end, desc = "Open response" },
        { "<leader>Ri", function() require("kulala").inspect() end, desc = "Inspect request" },
        { "<leader>Rt", function() require("kulala").show_stats() end, desc = "Show request stats" },
    },
    init = function()
        vim.filetype.add({
            extension = {
                http = "http",
                rest = "rest",
            },
        })
    end,
    opts = {
        global_keymaps = false,
        global_keymaps_prefix = "<leader>R",
        kulala_keymaps = true,
        kulala_keymaps_prefix = "",
        default_env = "dev",
        ui = {
            display_mode = "split",
            split_direction = "vertical",
            default_view = "body",
            winbar = true,
            show_icons = "on_request",
        },
        lsp = {
            enable = true,
            keymaps = false,
        },
    },
}
