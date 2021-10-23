if (vim.opt.compatible == true) then
    vim.opt.compatible = false
end

if vim.fn.executable('rg') == 1 then
	vim.g.rg_derive_root = true
end

-- Sets how many lines of history VIM has to remember
vim.opt.history = 2000

-- Set to auto read when a file is changed from the outside
vim.opt.autoread = true

-- Remember info about open buffers on close
vim.opt.shada = "!,%,'100,<50,s100"
vim.g.netrw_browse_split = 2
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
vim.g.netrw_localrmdir = 'rm -r'

--vim.cmd 'scriptencoding utf-8'
vim.opt.encoding = 'utf-8'
vim.g.fileencoding = 'utf-8'
-- Use Unix as the standard file type
vim.opt.ffs = 'unix,dos,mac'

-- Use zsh shell
vim.g.shell = "/bin/zsh"

-- Use xclip to copy and paste
vim.opt.clipboard:append('unnamedplus')

-------------------------------------------------------------
-- => VIM user interface
---------------------------------------------------------------
-- Colors and fonts
--Set colorscheme (order is important here)
vim.o.termguicolors = true
vim.g.nord_terminal_italics = 2
vim.cmd [[colorscheme nord]]
-- vim.g.onedark_terminal_italics = 2
-- vim.cmd [[colorscheme onedark]]

vim.cmd('syntax on')
-- add vertical lines on columns
vim.opt.colorcolumn = '120,150'
vim.opt.cursorline = true

-- Always show current position
vim.opt.ruler = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.title = true
vim.opt.showcmd = true
vim.opt.cmdheight = 1
vim.opt.laststatus = 2
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.g.completion_matching_strategy_list = {'exact', 'substring', 'fuzzy'}
-- Highlight problematic whitespace
vim.opt.list = true
vim.opt.listchars = 'tab:» ,trail:•,extends:#,nbsp:.'

-- incremental substitution (neovim)
if vim.fn.has('nvim') == 1 then
   vim.o.inccommand = 'split'
end

vim.opt.showcmd = false
vim.opt.ruler = false

-- Don't redraw while executing macros (good performance config)
vim.opt.lazyredraw = true

-- Send more characters for redraws
vim.opt.ttyfast = true

-- Show matching brackets when text indicator is over them
vim.opt.showmatch = true

-- How many tenths of a second to blink when matching brackets
vim.opt.mat = 2

-- No annoying sound on errors
vim.opt.errorbells = false
vim.opt.visualbell = false
vim.opt.tm = 500

vim.opt.hidden = true

-- For conceal markers.
if vim.fn.has('conceal') == 1 then
  vim.opt.conceallevel = 2
  vim.opt.concealcursor = 'niv'
end

-- Autocompletion options
vim.opt.wildmenu = true
vim.opt.wildmode = 'list:longest,full'
vim.opt.complete = '.,w,b'
vim.opt.completeopt = { 'menuone', 'noinsert', 'noselect' }
-- Finding files - Search down into subfolders
vim.opt.path:append('**')
vim.opt.wildignore = [[
.git,.hg,.svn
*/node_modules/*
*.aux,*.out,*.toc
*.o,*.obj,*.exe,*.dll,*.manifest,*.rbc,*.class
*.ai,*.bmp,*.gif,*.ico,*.jpg,*.jpeg,*.png,*.psd,*.webp
*.avi,*.divx,*.mp4,*.webm,*.mov,*.m2ts,*.mkv,*.vob,*.mpg,*.mpeg
*.mp3,*.oga,*.ogg,*.wav,*.flac
*.eot,*.otf,*.ttf,*.woff
*.doc,*.pdf,*.cbr,*.cbz
*.zip,*.tar.gz,*.tar.bz2,*.rar,*.tar.xz,*.kgb
*.swp,.lock,.DS_Store,._*
]]
vim.opt.scl = 'yes'

-- Add asterisks in block comments
vim.opt.formatoptions:append('r')

-- Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
-- delays and poor user experience.
vim.opt.updatetime = 50

-- Don't pass messages to |ins-completion-menu|.
-- vim.opt.shortmess:append('s')
vim.opt.shortmess:append('c')

vim.opt.suffixesadd = '.js,.es,.jsx,.json,.css,.less,.sass,.styl,.php,.py,.md,.go,.ts,.tsx'

---------------------------------------------------------------
-- => Text, tab, indent and folding
---------------------------------------------------------------
-- We want true tabs but represent them in the file as four spaces
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
--vim.opt.expandtab = false
-- Be smart when using tabs ;)
vim.opt.smarttab = true

--No annoying word wrapping
vim.opt.textwidth = 0         -- You can wrap by selecting the offendig paragraph ('vap') and formatting ('gq')

vim.cmd 'filetype indent on'
vim.opt.ai = true  -- Auto indent
vim.opt.si = true   -- Smart indent
vim.opt.wrap = false -- No Wrap lines

-- Toggle paste mode
vim.opt.pastetoggle = '<F2>'

vim.opt.backspace = { 'indent', 'eol', 'start' }

-- Ignore case when searching
vim.opt.ignorecase = true

-- For regular expressions turn magic on
vim.opt.magic = true

-- set spell
-- set spelllang=ca_ca,es_es,en_us

 -- Folding
vim.opt.foldenable = true
-- set foldmethod=indent
vim.opt.foldmethod = 'syntax'
vim.opt.foldlevelstart = 99

vim.opt.guifont = 'JetBrains Mono Regular Nerd Font Complete Mono:h12'
--vim.opt.guioptions:remove('L')
---------------------------------------------------------------
-- => Files, backups and undo
----------------------------------------------------------------
-- Turn backup off, since most stuff is in SVC anyway...
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.undodir = vim.env.HOME.."/.cache/nvim/undodir"

-- Plugins
-- vim-json
vim.g.vim_json_syntax_conceal = 0
-- vim-markdown
vim.g.markdown_syntax_conceal = 0
