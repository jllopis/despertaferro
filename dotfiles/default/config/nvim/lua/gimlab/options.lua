-- LSP activation (references lsp/<filename>
vim.lsp.enable({
    "lua",
    "go",
    "terraform",
    "yaml",
    "ansible",
    "marksman",
    -- "write-good",
    -- "woke", -- permission issues with macOS .Trash
    -- "tailwind",
    "docker-compose",
    -- "bicep",
    -- "proselint",
    "python",
    -- "elixir",
    "json",
    "bash",
    "kulala_ls",
    "zls",
})

-- set utf8 as standard encoding
--vim.cmd 'scriptencoding utf-8'
vim.opt.encoding = 'utf8'
vim.g.fileencoding = 'utf-8'

-- use Unix as the standard file type
vim.opt.ffs = 'unix,dos,mac'

-- Sets how many lines of history VIM has to remember
vim.opt.history = 2000

-- Set to auto read when a file is changed from the outside
vim.opt.autoread = true
-- Automatically save before :next, :make etc.
vim.opt.autowrite = true

vim.opt.conceallevel = 1

-- Use zsh shell
if vim.loop.os_uname().sysname == "Linux" then
    vim.opt.shell = '/usr/bin/zsh'
elseif vim.loop.os_uname().sysname == 'Darwin' or vim.loop.os_uname().sysname == 'Mac' then
    vim.opt.shell = '/usr/local/bin/zsh'
end

-- In many terminal emulators the mouse works just fine, thus enable it.
if vim.fn.has('mouse') == 1 then
        vim.opt.mouse = 'a'
end

-----------------------------------------------------------------
-- => VIM user interface
-----------------------------------------------------------------
-- add vertical lines on columns
vim.opt.colorcolumn = '120,150'
vim.opt.cursorline = true

vim.opt.ruler = true

vim.opt.number = true
vim.opt.relativenumber = true

vim.opt.title = true
vim.opt.showcmd = true
vim.opt.cmdheight = 1
vim.opt.laststatus = 2

if vim.fn.has('scrolloff') == 0 then
        vim.opt.scrolloff = 10
end
if vim.fn.has('sidescrolloff') == 0 then
        vim.opt.sidescrolloff = 5
end

vim.opt.isfname:append('@-@')
vim.opt.display:append('lastline')

-- config search
vim.opt.smartcase = true -- ... but not when search pattern contains upper case characters
-- Highlight found searches
vim.opt.hlsearch = false
-- Shows the match while typing
vim.opt.incsearch = true
vim.g.completion_matching_strategy_list = {'exact', 'substring', 'fuzzy'}
-- Highlight problematic whitespace
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', extends = '#', nbsp = '␣' }

-- incremental substitution (neovim)
if vim.fn.has('nvim') == 1 then
   vim.o.inccommand = 'split'
end

-- Send more characters for redraws
vim.opt.ttyfast = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- How many tenths of a second to blink when matching brackets
vim.opt.mat = 2

-- No annoying sound on errors
vim.opt.errorbells = false
vim.opt.visualbell = false

vim.opt.hidden = true
-- Time out on key codes but not mappings.
-- Basically this makes terminal Vim work sanely.
vim.opt.timeout = false
vim.opt.ttimeoutlen = 10
-- By default timeoutlen is 1000 ms
vim.opt.timeoutlen=500
--set tm=500
vim.opt.tm = 500
vim.opt.updatetime = 50

vim.opt.backspace = 'indent,eol,start'  -- Makes backspace key more powerful.
vim.opt.showcmd = false
-- vim.opt.showcmd                     " Show me what I'm typing

vim.opt.splitright = true   -- Split vertical windows right to the current windows
vim.opt.splitbelow = true   -- Split horizontal windows below to the current windows

--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
--" => Text, tab, indent and folding
--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- We want true tabs but represent them in the file as four spaces
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smarttab = true
vim.opt.smartindent = true
vim.opt.autoindent = true

--No annoying word wrapping
--vim.opt.textwidth = 0  -- hi ha la opció de seleccionar el paragraf ('vap') i formatejar-lo ('gq')
-- vim.opt.wrap = false
-- Automatically soft-wrap text (only visually) at 80 columns:

vim.opt.textwidth = 0
vim.opt.wrapmargin = 0
vim.opt.wrap = true
vim.opt.linebreak = true -- (optional - breaks by word rather than character)
-- vim.opt.columns=80


-- Toggle paste mode
-- vim.opt.pastetoggle = '<F2>'

-- Ignore case when searching
vim.opt.ignorecase = true

-- For regular expressions turn magic on
vim.opt.magic = true

 -- Folding
vim.opt.foldenable = true
-- set foldmethod=indent
vim.opt.foldmethod = 'syntax'
vim.opt.foldlevelstart = 99

--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
--" => Files, backups and undo
--"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
-- Remember info about open buffers on close
vim.opt.shada = "!,%,'100,<50,s100"

-- Turn backup off, since most stuff is in SVC anyway...
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.undodir = vim.env.HOME.."/.cache/nvim/undodir"

------------------------------------------------------
--- Colors and fonts
------------------------------------------------------

---Set colorscheme (order is important here)
vim.opt.termguicolors = true
if vim.fn.has('termguicolors') == 1 then    --- set true colors
    vim.cmd 'set t_8f=[[38;2;%lu;%lu;%lum'
    vim.cmd 'set t_8b=[[48;2;%lu;%lu;%lum'
    vim.opt.termguicolors = true
end

--- speed up syntax highlighting
vim.opt.cursorcolumn = false
vim.opt.cursorline = true
vim.opt.synmaxcol = 300
vim.opt.re = 1

-- Set cursor line color on visual mode
--vim.cmd [[highlight Visual cterm=NONE ctermbg=236 ctermfg=NONE guibg=Grey30]]
--vim.cmd [[highlight LineNr cterm=NONE ctermfg=230 guifg=Grey50 guibg=#343949]]

vim.opt.background = 'dark'

