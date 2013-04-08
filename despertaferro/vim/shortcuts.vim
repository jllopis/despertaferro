" Change dir to the one of the editing file
" More on http://vim.wikia.com/wiki/Set_working_directory_to_the_current_file
nnoremap ,cd :cd %:p:h<CR>:pwd<CR>

" Save and restore session shorcuts
nmap <leader>ss :call SaveSession()<CR><CR>
nmap <leader>sr :call RestoreSession()<CR><CR>
