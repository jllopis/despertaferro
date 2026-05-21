-- Vim options and settings

local opt = vim.opt

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Display
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.wrap = false
opt.termguicolors = true

-- Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true

-- Performance
opt.updatetime = 250

-- Splits
opt.splitright = true
opt.splitbelow = true
