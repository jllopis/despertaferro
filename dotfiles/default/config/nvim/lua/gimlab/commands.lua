-- Syntax highlighting and filetype plugins
vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

--- Explicitly tell vim that the terminal supports 256 colors
vim.cmd 'set t_Co=256'

-- have a fixed column for the diagnostics to appear in
-- this removes the jitter when warnings/errors flow in
vim.cmd 'set signcolumn=yes'

-- No visual bell
vim.cmd 'set t_vb='

vim.cmd 'au FocusLost * :wa' -- Set vim to save the file on focus out.

vim.cmd 'syntax sync minlines=256'

