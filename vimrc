" Use Vim settings, rather then Vi settings (much better!).
" This must be first, because it changes other options as a side effect.
set nocompatible

" ================ General Config ====================
set number                              "Line numbers are good
set backspace=indent,eol,start          "Allow backspace in insert mode
set history=1000                        "Store lots of :cmdline history
set gcr=a:blinkon0                      "Disable cursor blink
set visualbell                          "No sounds
set autoread                            "Reload files changed outside vim
set mouse=a                             "Activate Mouse Support
set ruler                               "Show the line and column number of the cursor position
set clipboard^=unnamed,unnamedplus      "Use all clipboard register
set rtp+=/opt/homebrew/opt/fzf          "Enable fuzzy search

" This makes vim act like all other editors, buffers can
" exist in the background without being in a window.
" http://items.sjbach.com/319/configuring-vim-right
set hidden

"turn on syntax highlighting
syntax on

" Change leader to a comma because the backslash is too far away
" That means all \x commands turn into ,x
" The mapleader has to be set before vundle starts loading all
" the plugins.
let mapleader=" "

" =============== Plugin Initialization ===============
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
        \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif
call plug#begin()
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'flazz/vim-colorschemes'
Plug 'morhetz/gruvbox'
Plug '/usr/local/opt/fzf'
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
Plug 'tpope/vim-commentary'
Plug 'ervandew/supertab'
Plug 'lambdalisue/vim-manpager'
Plug 'derekprior/vim-trimmer'
Plug 'catppuccin/vim', { 'as': 'catppuccin' }
call plug#end()

"" fix background gets dark on scrolling
if &term =~ '256color'
  " Disable Background Color Erase (BCE) so that color schemes
  " work properly when Vim is used inside tmux and GNU screen.
  set t_ut=
endif


" ================ Turn Off Swap Files ==============
set noswapfile
set nobackup
set nowb

" ================ Persistent Undo ==================
" Keep undo history across sessions, by storing in file.
" Only works all the time.
if has('persistent_undo') && isdirectory(expand('~').'/.vim/backups')
  silent !mkdir ~/.vim/backups > /dev/null 2>&1
  set undodir=~/.vim/backups
  set undofile
endif

" ================ Indentation ======================
set autoindent
set smartindent
set smarttab
set shiftwidth=2
set softtabstop=2
set tabstop=2
set expandtab

" Auto indent pasted text
nnoremap p p=`]<C-o>
nnoremap P P=`]<C-o>

filetype plugin on
filetype indent on

" Display tabs and trailing spaces visually
set list listchars=tab:\ \ ,trail:·

set nowrap       "Don't wrap lines
set linebreak    "Wrap lines at convenient points

" ================ Folds ============================
set foldmethod=indent   "fold based on indent
set foldnestmax=3       "deepest fold is 3 levels
set nofoldenable        "dont fold by default

" ================ Completion =======================
set wildmode=list:longest
set wildmenu                "enable ctrl-n and ctrl-p to scroll thru matches
set wildignore=*.o,*.obj,*~ "stuff to ignore when tab completing
set wildignore+=*vim/backups*
set wildignore+=*sass-cache*
set wildignore+=*DS_Store*
set wildignore+=vendor/rails/**
set wildignore+=vendor/cache/**
set wildignore+=*.gem
set wildignore+=log/**
set wildignore+=tmp/**
set wildignore+=*.png,*.jpg,*.gif

" ================ Scrolling ========================
set scrolloff=8         "Start scrolling when we're 8 lines away from margins
set sidescrolloff=15
set sidescroll=1

" ================ Search ===========================
set incsearch       " Find the next match as we type the search
set hlsearch        " Highlight searches by default
set ignorecase      " Ignore case when searching...
set smartcase       " ...unless we type a capital

" ================ Security ==========================
set modelines=0
set nomodeline

" ================ Custom Settings ========================

"" my shortcuts -------------------------------
" simple vertical splits
map <leader>v <C-w>v

" Switch between the last two files
nnoremap <Leader><Leader> <C-^>

" Save and quit
map s :w<CR>
map Q :qa<CR>

" Window navigation
map <leader>h <C-w>h
map <leader>l <C-w>l


"" airline options --------------------------------
set noshowmode
set noshowcmd
set shortmess+=F
let g:airline_theme='catppuccin_mocha'
let g:airline_extensions = []
let g:airline_highlighting_cache = 1


"" theme options ----------------------------------
set termguicolors
colorscheme catppuccin_mocha

hi Normal guibg=NONE ctermbg=NONE


"" alacritty -------------------------------------
if $TERM == 'alacritty'
  set ttymouse=sgr
endif


"" NerdTree options and autocmds
autocmd VimEnter * NERDTreeFind | wincmd p
" Close the tab if NERDTree is the only window remaining in it.
autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif
map ; :Files ~<CR>


"" linenumbers autocmds
autocmd InsertEnter * :set norelativenumber
autocmd InsertLeave * :set relativenumber
