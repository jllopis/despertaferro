-- Return to last edit position when opening files (You want this!)
vim.api.nvim_exec(
  [[
  	autocmd!
	autocmd BufReadPost *
     		\ if line("'\"") > 0 && line("'\"") <= line("$") |
     		\   exe "normal! g`\"" |
     		\ endif
  ]],
  false
)

-- Turn off paste mode when leaving insert
vim.api.nvim_exec(
	[[
		autocmd!
		autocmd InsertLeave * set nopaste
	]],
	false
)

------------------------------------------------------
-- Syntax mapping
------------------------------------------------------
vim.api.nvim_exec(
	[[
		autocmd!
		autocmd FileType yaml setlocal shiftwidth=4 tabstop=4
		autocmd FileType javascript setlocal shiftwidth=4 tabstop=4
		autocmd FileType typescript setlocal shiftwidth=4 tabstop=4
		autocmd BufNewFile,BufReadPost *.md,*.markdown set filetype=markdown
		autocmd FileType go setlocal shiftwidth=4 tabstop=4 noexpandtab
		autocmd BufNewFile,BufReadPost *.tf,*.hcl set filetype=terraform
	]],
	false
)

vim.api.nvim_exec(
	[[
		au BufNewFile,BufRead *.es6 setf javascript
		au BufNewFile,BufRead *.tsx setf typescript
		au BufNewFile,BufRead *.ts setf typescript
		au BufNewFile,BufRead *.md set filetype=markdown
	]],
	false
)

-- Instead of reverting the cursor to the last position in the buffer, we
-- set it to the first line when editing a git commit message
vim.api.nvim_exec(
	[[
		au FileType gitcommit au! BufEnter COMMIT_EDITMSG call setpos('.', [0, 1, 1, 0])
	]],
	false
)

-- Set cursor line color on visual mode
vim.api.nvim_exec(
	[[
		highlight Visual cterm=NONE ctermbg=236 ctermfg=NONE guibg=Grey30
		highlight LineNr cterm=NONE ctermfg=230 guifg=Grey50 guibg=#343949
	]],
	false
)
