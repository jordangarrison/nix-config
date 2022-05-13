set mouse=a
set timeoutlen=0

" Leader & Shell
let mapleader='<Space>'
set shell=/run/current-system/sw/bin/zsh


" Unix
set encoding=utf-8

" Tabs as spaces
set expandtab
set tabstop=2
set softtabstop=2
set shiftwidth=2

" Tab completion
inoremap <expr> <TAB> pumvisible() ? "\<C-y>" : "\<CR>"
inoremap <expr> <Esc> pumvisible() ? "\<C-e>" : "\<Esc>"
inoremap <expr> <C-j> pumvisible() ? "\<C-n>" : "\<Down>"
inoremap <expr> <C-k> pumvisible() ? "\<C-p>" : "\<Up>"

function! s:check_back_space() abort
	let col = col('.') - 1
	return !col || getline('.')[col - 1] =~ '\s'
endfunction

inoremap <silent><expr> <Tab>
	\ pumvisible() ? "\<C-n>" :
	\ <SID>check_back_space() ? "\<Tab>" :
	\ kite#completion#autocomplete()
