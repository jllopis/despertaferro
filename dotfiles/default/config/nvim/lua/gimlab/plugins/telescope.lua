return {
    'nvim-telescope/telescope.nvim', version = '*',
    dependencies = {
        "nvim-lua/plenary.nvim",
        { "nvim-treesitter/nvim-treesitter",          build = ":TSUpdate" },
        { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
        "nvim-tree/nvim-web-devicons",
    },
    config = function()
        local telescope = require('telescope')
        local builtin = require('telescope.builtin')
        local actions = require('telescope.actions')

        telescope.setup({
            defaults = {
                mappings = {
                    i = {
                        ["C-k"] = actions.move_selection_previous,
                        ["C-j"] = actions.move_selection_next,
                        ["C-q"] = actions.send_selected_to_qflist + actions.open_qflist,
                        ["?"] = "which_key"
                    }
                }
            }
        })

        telescope.load_extension("fzf");

        vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = "Fuzzy find files in CWD" })
        vim.keymap.set('n', '<leader>fg', builtin.git_files, { desc = "Fuzzy find files managed by git" })
        vim.keymap.set('n', '<leader>fr', builtin.oldfiles, { desc = "Fuzzy find recent files" })
        vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = "Fuzzy find in buffers list" })
        -- vim.keymap.set('n', '<leader>fs', function()
        -- 	builtin.grep_string( { search = vim.fn.input("SEARCH => " ) } );
        -- end, { desc = "Find string in cwd" })
        vim.keymap.set('n', '<leader>fs', builtin.live_grep, { desc = "Find string in cwd" })
        vim.keymap.set('n', '<leader>fc', builtin.grep_string, { desc = "Find string under the cursor in cwd" })
    end
}
