-- Global keymaps

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- CONFIGURATION
map("n", "<leader>r", "<cmd>source ~/.config/nvim/init.lua<CR>:filetype detect<CR>:echo 'init.lua reloaded'<CR>", opts)
map("n", "<leader>cd", "<cmd>cd %:p:h<CR>:pwd<CR>", opts)

-- EDITION
map("v", "J", ":m '>+1<CR>gv=gv", opts)
map("v", "K", ":m '<-2<CR>gv=gv", opts)
map("n", "J", "mzJ`z", opts)
map("n", "<C-d>", "<C-d>zz", opts)
map("n", "<C-u>", "<C-u>zz", opts)
map("n", "n", "nzzzv", opts)
map("n", "N", "Nzzzv", opts)
map("x", "<leader>p", '"_dP', opts)
map("n", "Y", "yg$", opts)
map("n", "<leader>d", '"_d', opts)
map("v", "<leader>d", '"_d', opts)
map({ "n", "v", "x" }, "gy", '"+y', opts)
map({ "n", "v", "x" }, "gp", '"+p', opts)
map("n", "gY", '"+Y', opts)
map("n", "<leader>s", ":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>", opts)
map("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })

-- TABS
map("", "te", ":tabedit<CR>", opts)
map("", "<S-Tab>", ":tabprev<Return>", opts)
map("", "<Tab>", ":tabnext<CR>", opts)
map("", "<leader>tn", ":tabnew<CR>", opts)
map("", "<leader>to", ":tabonly<CR>", opts)
map("", "<leader>tc", ":tabclose<CR>", opts)
map("", "<leader>tm", ":tabmove", opts)
map("", "<leader>tk", ":tabnext<CR>", opts)
map("", "<leader>tj", ":tabprevious<CR>", opts)

-- Toggle between current and last tab
vim.g.lasttab = 1
map("n", "<Leader>tl", [[:exe "tabn ".g:lasttab<CR>]], { noremap = true, silent = true })
vim.api.nvim_create_autocmd("TabLeave", {
  pattern = "*",
  command = [[let g:lasttab = tabpagenr()]],
})

-- WINDOWS
map("n", "<leader>+", ":vertical resize +5<CR>", opts)
map("n", "<leader>-", ":vertical resize -5<CR>", opts)
map("n", "<leader>rp", ":resize 100<CR>", opts)
map("n", "ss", ":split<CR><C-w>w", { silent = true })
map("n", "sv", ":vsplit<CR><C-w>w", { silent = true })
map("n", ",", "<C-w>w", { silent = true })
map("n", "s<left>", "<C-w>h", { silent = true })
map("n", "s<up>", "<C-w>k", { silent = true })
map("n", "s<down>", "<C-w>j", { silent = true })
map("n", "s<right>", "<C-w>l", { silent = true })
map("n", "sh", "<C-w>h", { silent = true })
map("n", "sk", "<C-w>k", { silent = true })
map("n", "sj", "<C-w>j", { silent = true })
map("n", "sl", "<C-w>l", { silent = true })
map("n", "<C-w><left>", "<C-w><", { silent = true })
map("n", "<C-w><right>", "<C-w>>", { silent = true })
map("n", "<C-w><up>", "<C-w>+", { silent = true })
map("n", "<C-w><down>", "<C-w>-", { silent = true })

-- TERMINAL
map("n", "<leader>o", ":below 10sp term://$SHELL<cr>i", { noremap = true, silent = true })

-- OTHERS
map("n", "<leader>f", vim.lsp.buf.format, opts)
map("n", "<leader><leader>", function() vim.cmd("so") end, opts)
map("n", "<leader>w", function()
  vim.opt.wrap = not vim.opt.wrap:get()
  local status = vim.opt.wrap:get() and "enabled" or "disabled"
  vim.notify("Word wrap " .. status)
end, opts)

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>", opts)
