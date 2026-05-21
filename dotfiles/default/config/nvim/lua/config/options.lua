-- Vim options and settings

local opt = vim.opt

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ENCODING
opt.encoding = "utf8"
vim.g.fileencoding = "utf-8"
opt.ffs = "unix,dos,mac"

-- HISTORY & PERSISTENCE
opt.history = 2000
opt.autoread = true
opt.autowrite = true
opt.shada = "!,%,'100,<50,s100"

-- FILE HANDLING
opt.backup = false
opt.writebackup = false
opt.swapfile = false
opt.undofile = true
opt.undodir = vim.env.HOME .. "/.cache/nvim/undodir"

-- DISPLAY & UI
opt.number = true
opt.relativenumber = true
opt.title = true
opt.showcmd = false
opt.cmdheight = 1
opt.laststatus = 2
opt.ruler = true
opt.signcolumn = "yes"
opt.colorcolumn = "120,150"
opt.cursorline = true
opt.cursorcolumn = false
opt.background = "dark"
opt.termguicolors = true
opt.conceallevel = 1

-- MOUSE & SCROLLING
if vim.fn.has("mouse") == 1 then
  opt.mouse = "a"
end
if vim.fn.has("scrolloff") == 1 then
  opt.scrolloff = 10
end
if vim.fn.has("sidescrolloff") == 1 then
  opt.sidescrolloff = 5
end

-- SEARCH & SUBSTITUTION
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.incsearch = true
opt.magic = true
if vim.fn.has("nvim") == 1 then
  vim.o.inccommand = "split"
end

-- WHITESPACE VISUALIZATION
opt.list = true
opt.listchars = { tab = "» ", trail = "·", extends = "#", nbsp = "␣" }

-- INDENTATION & TEXT
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smarttab = true
opt.smartindent = true
opt.autoindent = true
opt.textwidth = 0
opt.wrapmargin = 0
opt.wrap = false
opt.linebreak = true

-- FOLDING
opt.foldenable = true
opt.foldmethod = "syntax"
opt.foldlevelstart = 99

-- SYNTAX & PERFORMANCE
opt.synmaxcol = 300
opt.re = 1
opt.ttyfast = true
opt.updatetime = 50

-- BUFFER & ERRORS
opt.hidden = true
opt.backspace = "indent,eol,start"
opt.errorbells = false
opt.visualbell = false

-- TIMEOUT
opt.timeout = false
opt.ttimeoutlen = 10
opt.timeoutlen = 500
opt.tm = 500

-- SPECIAL CHARACTERS
opt.isfname:append("@-@")
opt.display:append("lastline")

-- MATCHING
opt.showmatch = true
opt.mat = 2

-- SHELL DETECTION
if vim.loop.os_uname().sysname == "Linux" then
  opt.shell = "/usr/bin/zsh"
elseif vim.loop.os_uname().sysname == "Darwin" then
  opt.shell = "/usr/local/bin/zsh"
end

-- SPLITS
opt.splitright = true
opt.splitbelow = true
