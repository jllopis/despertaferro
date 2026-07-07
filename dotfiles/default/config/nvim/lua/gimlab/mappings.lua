local opts = { noremap = true, silent = true }

-- Leader key
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '


vim.keymap.set('n', '<leader>r', "<cmd>:source ~/.config/nvim/init.lua<CR>:filetype detect<CR>:exe \":echo 'init.lua reloaded'\"<CR> \" reload config file", opts)

---------------------------------------------------------------------------------
---  Edition
---------------------------------------------------------------------------------
--- Switch CWD to the directory of the open buffer
vim.keymap.set('n', '<leader>cd', "<cmd>:cd %:p:h<CR>:pwd", opts)

vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", opts)
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", opts)

vim.keymap.set('n', 'J', "mzJ`z", opts)
vim.keymap.set('n', '<C-d>', "<C-d>zz", opts)
vim.keymap.set('n', '<C-u>', "<C-u>zz", opts)
vim.keymap.set('n', 'n', "nzzzv", opts)
vim.keymap.set('n', 'N', "Nzzzv", opts)

vim.keymap.set('x', '<leader>p', "\"_dP", opts) --- per no perdre la selecció anterior a l'enganyar sobre un altra
vim.keymap.set('n', 'Y', "yg$", opts)  ---" Yank from the cursor to the end of the line

vim.keymap.set('n', '<leader>d', "\"_d", opts) --- esborra el 'void register'
vim.keymap.set('v', '<leader>d', "\"_d", opts) --- esborra el 'void register'

vim.keymap.set({'n', 'v', 'x'}, 'gy', '"+y') -- copia al porta retalls
vim.keymap.set({'n', 'v', 'x'}, 'gp', '"+p') -- enganxa des del porta retalls
vim.keymap.set('n', 'gY', '"+Y', opts)  -- Copia des d'el cursor fins al final de la línia al portaretalls

-------------------------------------------------------------------------------
--  Tabs
-------------------------------------------------------------------------------
-- Open current directory
-- vim.keymap.set te :tabedit <c-r>=expand("%:p:h")<cr>/
vim.keymap.set('', 'te', ":tabedit <CR>=vim.fn.expand(\"%:p:h\")<CR>", opts)
vim.keymap.set('', '<S-Tab>', ":tabprev<Return>", opts)
vim.keymap.set('', '<Tab>', "tabnext<CR>", opts)
vim.keymap.set('', '<leader>tn', ":tabnew<CR>", opts)
vim.keymap.set('', '<leader>to', ":tabonly<CR>", opts)
vim.keymap.set('', '<leader>tc', ":tabclose<CR>", opts)
vim.keymap.set('', '<leader>tm', ":tabmove", opts)
vim.keymap.set('', '<leader>tk', ":tabnext<CR>", opts)
vim.keymap.set('', '<leader>tj', ":tabprevious<CR>", opts)
-- Let 'tl' toggle between this and the last accessed tab
vim.g.lasttab = 1
vim.keymap.set('n', '<Leader>tl', [[:exe "tabn ".g:lasttab<CR>]], { noremap = true, silent = true })
vim.api.nvim_create_autocmd("TabLeave", {
    pattern = '*',
    command = [[
        let g:lasttab = tabpagenr()
    ]]
})

---------------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------------
-- window resize
vim.keymap.set('n', '<leader>+', [[:vertical resize +5<CR>]], { noremap = true, silent = true })
vim.keymap.set('n', '<leader>-', [[:vertical resize -5<CR>]], { noremap = true, silent = true })
vim.keymap.set('n', '<leader>rp', [[:resize 100<CR>]], { noremap = true, silent = true })

-- Split window
vim.keymap.set('n', 'ss', [[:split<CR><C-w>w]], {silent = true })
vim.keymap.set('n', 'sv', [[:vsplit<CR><C-w>w]], {silent = true })
-- Move window
vim.keymap.set('n', ',', [[<C-w>w]], {silent = true })
vim.keymap.set('n', 's<left>', [[<C-w>h]], {silent = true })
vim.keymap.set('n', 's<up>', [[<C-w>k]], {silent = true })
vim.keymap.set('n', 's<down>', [[<C-w>j]], {silent = true })
vim.keymap.set('n', 's<right>', [[<C-w>l]], {silent = true })
vim.keymap.set('n', 'sh', [[<C-w>h]], {silent = true })
vim.keymap.set('n', 'sk', [[<C-w>k]], {silent = true })
vim.keymap.set('n', 'sj', [[<C-w>j]], {silent = true })
vim.keymap.set('n', 'sl', [[<C-w>l]], {silent = true })
-- Resize window
vim.keymap.set('n', '<C-w><left>', [[<C-w><]], {silent = true })
vim.keymap.set('n', '<C-w><right>', [[<C-w>>]], {silent = true })
vim.keymap.set('n', '<C-w><up>', [[<C-w>+]], {silent = true })
vim.keymap.set('n', '<C-w><down>', [[<C-w>-]], {silent = true })

-- Open term in a split window 10lines hight below
vim.keymap.set('n', '<leader>o', [[:below 10sp term://$SHELL<cr>i]], { noremap = true, silent = true })

--- vim.keymap.set('n', '<C-f>', "<cmd>silent !tmux neww tmux-sessionizer<CR>") --- ThePrimeagen https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/scripts/tmux-sessionizer
vim.keymap.set('n', '<leader>f', function()
	vim.lsp.buf.format()
end)

---vim.keymap.set("n", "<C-k>", "<cmd>cnext<CR>zz", opts)
---vim.keymap.set("n", "<C-j>", "<cmd>cprev<CR>zz", opts)
---vim.keymap.set("n", "<leader>k", "<cmd>lnext<CR>zz", opts)
---vim.keymap.set("n", "<leader>j", "<cmd>lprev<CR>zz", opts)

vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], opts)
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

vim.keymap.set("n", "<leader>vpp", "<cmd>e ~/.config/nvim/lua/gim/lazy.lua<CR>", opts);
vim.keymap.set("n", "<leader>mr", "<cmd>CellularAutomaton make_it_rain<CR>", opts);

vim.keymap.set("n", "<leader><leader>", function()
    vim.cmd("so")
end)

--vim.keymap.set('n', '', "", opts)
