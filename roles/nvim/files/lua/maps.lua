local map = vim.api.nvim_set_keymap

map('n', '<Space>', '', {})
vim.g.mapleader = ' '

vim.api.nvim_set_keymap('n', '<leader>r', [[<cmd>:source ~/.config/nvim/init.lua<CR>:filetype detect<CR>:exe ":echo 'vimrc reloaded'"<CR> " reload config file]], { noremap = true, silent = true })

---------------------------------------------------------------------------------
--  Edition
---------------------------------------------------------------------------------
-- Switch CWD to the directory of the open buffer
vim.api.nvim_set_keymap('n', '<leader>cd', [[<cmd>:cd %:p:h<CR>:pwd<CR>]], {})

vim.api.nvim_set_keymap('v', 'J', [[:m '>+1<CR>gv=gv<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', 'K', [[:m '<-2<CR>gv=gv<CR>]], { noremap = true, silent = true })
--" Yank from the cursor to the end of the line, to be consistent with C and D.
vim.api.nvim_set_keymap('n', 'Y', [[y$]], { noremap = true, silent = true })


---------------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------------
-- window resize
vim.api.nvim_set_keymap('n', '<leader>+', [[:vertical resize +5<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>-', [[:vertical resize -5<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>rp', [[:resize 100<CR>]], { noremap = true, silent = true })

-- Split window
vim.api.nvim_set_keymap('n', 'ss', [[:split<CR><C-w>w]], {silent = true })
vim.api.nvim_set_keymap('n', 'sv', [[:vsplit<CR><C-w>w]], {silent = true })
-- Move window
vim.api.nvim_set_keymap('n', ',', [[<C-w>w]], {silent = true })
vim.api.nvim_set_keymap('n', 's<left>', [[<C-w>h]], {silent = true })
vim.api.nvim_set_keymap('n', 's<up>', [[<C-w>k]], {silent = true })
vim.api.nvim_set_keymap('n', 's<down>', [[<C-w>j]], {silent = true })
vim.api.nvim_set_keymap('n', 's<right>', [[<C-w>l]], {silent = true })
vim.api.nvim_set_keymap('n', 'sh', [[<C-w>h]], {silent = true })
vim.api.nvim_set_keymap('n', 'sk', [[<C-w>k]], {silent = true })
vim.api.nvim_set_keymap('n', 'sj', [[<C-w>j]], {silent = true })
vim.api.nvim_set_keymap('n', 'sl', [[<C-w>l]], {silent = true })
-- Resize window
vim.api.nvim_set_keymap('n', '<C-w><left>', [[<C-w><]], {silent = true })
vim.api.nvim_set_keymap('n', '<C-w><right>', [[<C-w>>]], {silent = true })
vim.api.nvim_set_keymap('n', '<C-w><up>', [[<C-w>+]], {silent = true })
vim.api.nvim_set_keymap('n', '<C-w><down>', [[<C-w>-]], {silent = true })

-- Open term in a split window 10lines hight below
vim.api.nvim_set_keymap('n', '<leader>o', [[:below 10sp term://$SHELL<cr>i]], { noremap = true, silent = true })

-----------------------------------------------------------------
-- Fugitive
-----------------------------------------------------------------
vim.api.nvim_set_keymap('n', '<leader>gs', [[:Git<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>gd', [[:Gdiff<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>gc', [[:Gcommit<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>gb', [[:Gblame<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>gl', [[:Glog<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>gp', [[:Git push<CR>]], { noremap = true, silent = true })
-- Conflict Resolution
vim.api.nvim_set_keymap('n', 'gdh', [[:diffget //2<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', 'gdh', [[:diffget //3<CR>]], { noremap = true, silent = true })

vim.api.nvim_set_keymap('n', '<leader>gc', [[:GBranches<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>ga', [[:Git fetch --all<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>grum', [[:Git rebase upstream/master<CR>]], { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>grom', [[:Git rebase origin/master<CR>]], { noremap = true, silent = true })

-----------------------------------------------------------------
-- GitGutter
-----------------------------------------------------------------
-- vim.api.nvim_set_keymap('n', 'leader>gw', [[:Gwrite<CR>:GitGutter<CR>]], { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', '<leader>gg', [[:GitGutterToggle<CR>]], {silent = true })

