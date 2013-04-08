" Add dir of curr file to path
let s:default_path = escape(&path, '\ ') " store default value of 'path'

" Always add the current file's directory to the path and tags list if not
" already there. Add it to the beginning to speed up searches.
autocmd BufRead *
      \ let s:tempPath=escape(escape(expand("%:p:h"), ' '), '\ ') |
      \ exec "set path-=".s:tempPath |
      \ exec "set path-=".s:default_path |
      \ exec "set path^=".s:tempPath |
      \ exec "set path^=".s:default_path

" Run gofmt when save a go source file
autocmd BufWritePost *.go !gofmt -w %

"autocmd BufWinLeave * silent! mkview "make vim save view (state) (folds, cursor, etc)
"autocmd BufWinEnter * silent! loadview "make vim load view (state) (folds, cursor, etc)
