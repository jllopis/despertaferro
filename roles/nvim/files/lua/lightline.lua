--if vim.fn.exists('*fugitive#statusline') == 0 then
--  vim.opt.statusline = '%F %m%r%h%w%y%{'['.(&fenc!=''?&fenc:&enc).':'.&ff.']'}[L%l/%L,C%03v]'
--  vim.opt.statusline:append('%=')
--  vim.opt.statusline:appned('%{fugitive#statusline()}')
--end

-- custom lightline
vim.g.lightline = {
    colorscheme = 'nord';
    active = {
        left = {
            {
                'mode',
                'paste'
            },
            {
                'gitbranch',
                'readonly',
                'filename',
                'modified'
            }
        },
        right = {
            {
                'ale',
                'lineinfo',
                'percent',
            },
            { 'charcode', 'fileformat', 'filetype' },
            {'linter_checking', 'linter_errors', 'linter_warnings', 'linter_infos', 'linter_ok'}
        }
    };

    inactive = {
        left = {
            {
                'gitbranch',
                'readonly',
                'filename',
                'modified'
            }
        }
    };

    component = {
        filename = '%f',
    };

    component_function = {
        gitbranch = 'MyGitBranch',
        readonly = 'MyReadonly',
        modified = 'MyModified',
        ale = 'ALEGetStatusLine',
    };

    separator = { left = '', right = '' };
    subseparator = { left = '', right = '' };
}

vim.g['lightline.component_expand'] = {
       linter_checking = 'lightline#ale#checking',
       linter_infos = 'lightline#ale#infos',
       linter_warnings = 'lightline#ale#warnings',
       linter_errors = 'lightline#ale#errors',
       linter_ok = 'lightline#ale#ok',
}

vim.g['lightline.component_type'] = {
     linter_checking = 'right',
     linter_infos = 'right',
     linter_warnings = 'warning',
     linter_errors = 'error',
     linter_ok = 'right',
}

vim.g['lightline#ale#indicator_checking'] = ' ' -- 'uf110'
vim.g['lightline#ale#indicator_infos'] = '' -- 'uf129'
vim.g['lightline#ale#indicator_warnings'] = '' --'uf071'
vim.g['lightline#ale#indicator_errors'] = '' --'uf05e'
vim.g['lightline#ale#indicator_ok'] = '' -- 'uf00c'

vim.opt.showmode = false

vim.api.nvim_exec(
[[
function! MyModified()
  if &filetype == "help"
    return ""
  elseif &modified
    return "+"
  elseif &modifiable
    return ""
  else
    return ""
  endif
endfunction
]], false)

vim.api.nvim_exec(
[[
function! MyReadonly()
  if &filetype == "help"
    return ""
  elseif &readonly
    return "\u2b64"
  else
    return ""
  endif
endfunction
]], false)

vim.api.nvim_exec(
[[
function! MyGitBranch()
  let _ = fugitive#head()
  return strlen(_) ? ' '._ : ''
endfunction
]], false)
