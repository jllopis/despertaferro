" Save and restore sessions functions
if !exists("g:session_dir")
  let g:session_dir = $HOME . "/.vim/sessions"
endif

function! SaveSession()
  let name = split(getcwd(), "/")[-1]
  let session_file = g:session_dir . "/" . name . '.vim'
  execute 'mksession! ' . session_file
  echom "Session ". name . " saved!"
endfunction

function! RestoreSession()
  let name = split(getcwd(), "/")[-1]
  let session_file = g:session_dir . "/" . name . '.vim'
  if filereadable(session_file)
    execute 'so ' . session_file
      if bufexists(1)
        for l in range(1, bufnr('$'))
          if bufwinnr(l) == -1
            exec 'sbuffer ' . l
          endif
        endfor
      endif
   endif
   echom "Session " . name . " loaded!"
endfunction

