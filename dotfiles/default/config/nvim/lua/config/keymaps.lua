-- Global keymaps

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Basic editing
map("n", "<leader>w", "<cmd>w<cr>", opts)
map("n", "<leader>q", "<cmd>q<cr>", opts)

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>", opts)

-- Window navigation
map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)
map("n", "<C-l>", "<C-w>l", opts)

-- Window resize
map("n", "<C-Up>", "<cmd>resize +2<cr>", opts)
map("n", "<C-Down>", "<cmd>resize -2<cr>", opts)
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", opts)
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", opts)
