local actions = require('telescope.actions')

require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ["<C-j>"] = actions.move_selection_next,
        ["<C-k>"] = actions.move_selection_previous,
      },
    }
  },
}

-- Telescope fuzzy find stuff
--map('n', '<Leader>f.', '<Cmd>lua require(\'telescope.builtin\').find_files()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', 'sf', '<Cmd>lua require(\'telescope.builtin\').find_files()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>ff', '<Cmd>lua require(\'pluginsConfig.telescope\').search_workspace()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>fb', '<Cmd>lua require(\'telescope.builtin\').buffers()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>fg', '<Cmd>lua require(\'telescope.builtin\').live_grep()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>fh', '<Cmd>lua require(\'telescope.builtin\').help_tags()<CR>', { noremap = true, silent = true })

local M = {}
M.search_dotfiles = function()
  require('telescope.builtin').find_files({
    prompt_title = 'Configuration files',
    cwd = vim.fn['stdpath']('config'),
    file_ignore_patterns = { '.png' },
  })
end

M.search_workspace = function()
  require('telescope.builtin').find_files({
    prompt_title = 'Workspace files',
    cwd = vim.env.WORKSPACE,
    file_ignore_patterns = { '.docx', '.pdf' },
  })
end
return M

