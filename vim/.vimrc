set termguicolors
set t_Co=256
colorscheme default


augroup MyColors
  autocmd!
  autocmd ColorScheme * hi LineNr guifg=#999999
  autocmd ColorScheme * hi Normal guibg=#131313
  autocmd ColorScheme * hi EndOfBuffer guifg=#131313 guibg=#131313

  "Syntax highlighting
  autocmd ColorScheme * hi Comment    guifg=#6a9955    " Comments (green)
  autocmd ColorScheme * hi String     guifg=#ce9178    " Strings (orange)
  autocmd ColorScheme * hi Keyword    guifg=#569cd6    " Keywords (blue)
  autocmd ColorScheme * hi Function   guifg=#dcdcaa    " Functions (yellow)
  autocmd ColorScheme * hi Number     guifg=#b5cea8    " Numbers (light green)
  autocmd ColorScheme * hi Type       guifg=#4ec9b0    " Types (teal)
  autocmd ColorScheme * hi Constant   guifg=#4fc1ff    " Constants (cyan)
  autocmd ColorScheme * hi Identifier guifg=#9cdcfe    " Variables (light blue)
  autocmd ColorScheme * hi Statement  guifg=#c586c0    " Statements (purple)
  autocmd ColorScheme * hi PreProc    guifg=#c586c0    " Preprocessor (purple)
  autocmd ColorScheme * hi Special    guifg=#d4d4d4    " Special chars


  autocmd ColorScheme * hi Pmenu     guibg=#131313 guifg=#d4d4d4
  autocmd ColorScheme * hi PmenuSel  guibg=#262626 guifg=#ffffff
  autocmd ColorScheme * hi PmenuSbar guibg=#1c1c1c
  autocmd ColorScheme * hi PmenuThumb guibg=#444444

  autocmd ColorScheme * hi Visual guibg=#2a2a2a guifg=NONE

augroup END


" ============================================
" BASIC SETTINGS
" ============================================
let mapleader = " "
let maplocalleader = " "
set timeoutlen=400 
set number
syntax on
set mouse=a
set ignorecase
set smartcase
"this remove syntax highlighting from netrw
autocmd FileType netrw syntax clear

" allow to switch buffers even without saving
set hidden

set relativenumber

filetype plugin indent on

" Indentation
set tabstop=2       " Number of visual spaces per TAB
set shiftwidth=2    " Number of spaces to use for autoindent
set softtabstop=2   " Number of spaces in tab when editing
set expandtab       " Use spaces instead of tabs

" ============================================
" NETRW SETTINGS
" ============================================

let g:netrw_liststyle = 1   " Tree view
let g:netrw_banner = 0      " No banner
let g:netrw_winsize = 25    " Set width

" ============================================
" KEY MAPPINGS
" ============================================

" Map 'jj' to Escape in insert mode
inoremap jj <Esc>

" Map ';' to ':' in normal mode (saves Shift press)
nnoremap ; :

" Map Ctrl+C to copy to system clipboard in visual mode
vnoremap <C-c> "+y

" Open terminal in current buffer
nnoremap <leader>t :terminal<CR>


" ============================================
" MARKDOWN
" ============================================
" Reading .md in vim:
"   - headings fold (za/zc/zo), the file opens with folds open
"   - **bold**, _italic_, ~~strike~~ and `code` markers are concealed, so the
"     text looks closer to the rendered version (insert mode shows them again)
"   - long lines wrap at word boundaries; j/k follow the displayed lines
"     (counts such as 5j still move by file lines)
"   - [[ and ]] jump between headings (built into vim's markdown ftplugin)
"   - <leader>m toggles conceal, <leader>s toggles spell check
"
" g:markdown_folding must be set before the markdown ftplugin is sourced.
let g:markdown_folding = 1
let g:markdown_syntax_conceal = 1

function! s:MarkdownSetup() abort
  setlocal wrap linebreak nolist breakindent
  setlocal breakindentopt=shift:2
  setlocal conceallevel=2 concealcursor=n
  setlocal foldlevel=99
  setlocal norelativenumber
  setlocal spelllang=en_us
  " markdown reads better with 4 spaces; the global default is 2
  setlocal expandtab tabstop=4 shiftwidth=4 softtabstop=4
  nnoremap <buffer> <expr> j v:count == 0 ? 'gj' : 'j'
  nnoremap <buffer> <expr> k v:count == 0 ? 'gk' : 'k'
  nnoremap <buffer> <silent> <leader>m :<C-U>call <SID>MarkdownToggleConceal()<CR>
  nnoremap <buffer> <silent> <leader>s :<C-U>call <SID>MarkdownToggleSpell()<CR>
  " Undo local settings/maps when this buffer changes file type.
  let b:undo_ftplugin = get(b:, 'undo_ftplugin', '')
        \ . '|setlocal wrap< linebreak< list< breakindent< breakindentopt<'
        \ . ' conceallevel< concealcursor< foldlevel< relativenumber< spelllang< spell<'
        \ . '|silent! nunmap <buffer> j|silent! nunmap <buffer> k'
        \ . '|silent! nunmap <buffer> <leader>m|silent! nunmap <buffer> <leader>s'
endfunction

function! s:MarkdownToggleConceal() abort
  if &l:conceallevel > 0
    setlocal conceallevel=0
    echo "Markdown: raw markup"
  else
    setlocal conceallevel=2
    echo "Markdown: rendered"
  endif
endfunction

function! s:MarkdownToggleSpell() abort
  setlocal spell!
  echo "Markdown spell: " . (&l:spell ? "on" : "off")
endfunction

augroup MarkdownSettings
  autocmd!
  autocmd FileType markdown call <SID>MarkdownSetup()
augroup END

" Markdown-specific highlight groups, using the same palette as MyColors.
" Keep this in a function + ColorScheme autocmd so :colorscheme doesn't wipe it.
function! s:MarkdownHighlights() abort
  hi markdownH1                guifg=#569cd6 gui=bold
  hi markdownH2                guifg=#4ec9b0 gui=bold
  hi markdownH3                guifg=#dcdcaa gui=bold
  hi markdownH4                guifg=#c586c0 gui=bold
  hi markdownH5                guifg=#ce9178 gui=bold
  hi markdownH6                guifg=#9cdcfe gui=bold
  hi markdownHeadingDelimiter  guifg=#909090
  hi markdownCode              guifg=#ce9178
  hi markdownCodeBlock         guifg=#d4d4d4
  hi markdownCodeDelimiter     guifg=#909090
  hi markdownBold              guifg=#ffffff gui=bold
  hi markdownItalic            guifg=#d4d4d4 gui=italic
  hi markdownBoldItalic        guifg=#ffffff gui=bold,italic
  hi markdownStrike            guifg=#999999 gui=strikethrough
  hi markdownLinkText          guifg=#4fc1ff gui=underline
  hi markdownUrl               guifg=#6a9955
  hi markdownListMarker        guifg=#569cd6
  hi markdownOrderedListMarker guifg=#569cd6
  hi markdownBlockquote        guifg=#6a9955 gui=italic
  hi markdownRule              guifg=#909090
  hi markdownFootnote          guifg=#808080
  hi markdownFootnoteDefinition guifg=#808080
endfunction

augroup MarkdownColors
  autocmd!
  autocmd ColorScheme * call <SID>MarkdownHighlights()
augroup END
call s:MarkdownHighlights()


" ============================================
" VIM-PLUG PLUGIN MANAGER
" ============================================

" Auto-install vim-plug if not found
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Begin plugin section
call plug#begin('~/.vim/plugged')

" FZF plugins
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

Plug 'jiangmiao/auto-pairs'
" End plugin section
call plug#end()
" ============================================
" FZF.VIM CONFIGURATION
" ============================================

" Use ripgrep for faster file searching (install ripgrep for best results)
if executable('rg')
  let $FZF_DEFAULT_COMMAND = 'rg --files --hidden --follow --glob "!.git/*"'
  set grepprg=rg\ --vimgrep
  set grepformat=%f:%l:%c:%m
endif

" Layout: 95% width, 80% height, CENTERED
let g:fzf_layout = { 'window': { 'width': 0.95, 'height': 0.8 } }

" Show preview window on right (toggle with Ctrl-/)
let g:fzf_preview_window = ['right:50%', 'ctrl-/']

" Custom FZF highlight groups (lighter background)
augroup FZFColors
  autocmd!
  autocmd ColorScheme * hi FzfBg guibg=#333333
  autocmd ColorScheme * hi FzfCursorLine guibg=#3a3a3a guifg=#d4d4d4
augroup END

let g:fzf_colors = {
  \ 'fg':      ['fg', 'Normal'],
  \ 'bg':      ['bg', 'FzfBg'],
  \ 'hl':      ['fg', 'Keyword'],
  \ 'fg+':     ['fg', 'FzfCursorLine'],
  \ 'bg+':     ['bg', 'FzfCursorLine'],
  \ 'hl+':     ['fg', 'Statement'],
  \ 'info':    ['fg', 'PreProc'],
  \ 'border':  ['fg', 'Comment'],
  \ 'prompt':  ['fg', 'Function'],
  \ 'pointer': ['fg', 'Exception'],
  \ 'marker':  ['fg', 'Keyword'],
  \ 'spinner': ['fg', 'Label'],
  \ 'header':  ['fg', 'Comment']
  \ }

" FZF keybindings
" Space + f = find files
nnoremap <Leader>f :Files<CR>

" Space + g = grep/search text
nnoremap <Leader>g :Rg<CR>

" Space + b = buffers
nnoremap <Leader>b :Buffers<CR>

" Space + e = recent files (not <Leader>fh: it made <Leader>f wait for a 2nd key)
nnoremap <Leader>e :History<CR>

" Space + r = browse registers
nnoremap <Leader>r :Registers<CR>

" ============================================
" FZF REGISTERS
" ============================================

" Previews go in Vim's own temp dir (mode 700, removed when Vim exits), not
" /tmp: registers can hold passwords and tokens.
let s:regdir = fnamemodify(tempname(), ':h')

function! s:registers_list()
  let l:regs = '0123456789abcdefghijklmnopqrstuvwxyz"+-*/'
  let l:lines = []
  for i in range(len(l:regs))
    let l:r = l:regs[i]
    let l:content = getreg(l:r)
    if l:content !=# ''
      " Write register content to a temp file for preview
      let l:tmpfile = s:regdir . '/reg_' . char2nr(l:r)
      call writefile(split(l:content, '\n'), l:tmpfile)
      " Tag line with the char code so preview can find it
      let l:preview = substitute(l:content, '\n', '\\n', 'g')
      if len(l:preview) > 60
        let l:preview = l:preview[:60] . '...'
      endif
      call add(l:lines, printf('%d [%s]  %s', char2nr(l:r), l:r, l:preview))
    endif
  endfor
  return l:lines
endfunction

function! s:registers_sink(line)
  let l:reg = matchstr(a:line, '\[\zs.\ze\]')
  let l:content = getreg(l:reg)
  call setreg('+', l:content)
  echo 'Register "' . l:reg . '" copied to clipboard!'
endfunction

command! Registers call fzf#run(fzf#wrap({
  \ 'source': s:registers_list(),
  \ 'sink': function('s:registers_sink'),
  \ 'options': '--prompt="Registers> " --preview="cat ' . s:regdir . '/reg_{1}" --preview-window=right:50%:wrap'
  \ }))





" ── Harpoon-lite ────────────────────────────────────────────────────────────

let g:harpoon_marks = []

function! HarpoonAdd()
  let l:file = expand('%:p')
  if l:file == '' | echo "No file to mark" | return | endif
  if index(g:harpoon_marks, l:file) != -1
    echo "Already marked: " . expand('%:t')
    return
  endif
  if len(g:harpoon_marks) >= 9
    echo "Harpoon full (max 9). Remove one first with <leader>d"
    return
  endif
  call add(g:harpoon_marks, l:file)
  echo "Harpooned [" . len(g:harpoon_marks) . "/9]: " . expand('%:t')
endfunction

function! HarpoonRemove()
  let l:file = expand('%:p')
  let l:idx = index(g:harpoon_marks, l:file)
  if l:idx == -1
    echo "Not in harpoon list: " . expand('%:t')
    return
  endif
  call remove(g:harpoon_marks, l:idx)
  echo "Removed: " . expand('%:t')
endfunction

function! HarpoonRemoveAll()
  if empty(g:harpoon_marks) | echo "Harpoon list is already empty" | return | endif
  let l:count = len(g:harpoon_marks)
  let g:harpoon_marks = []
  echo "Harpoon cleared (" . l:count . " files removed)"
endfunction


function! HarpoonJump(slot)
  if empty(g:harpoon_marks) | echo "Harpoon list is empty" | return | endif
  let l:idx = a:slot == 9 ? len(g:harpoon_marks) - 1 : a:slot - 1
  if l:idx >= len(g:harpoon_marks)
    echo "Slot " . a:slot . " is empty"
    return
  endif
  execute 'edit ' . fnameescape(g:harpoon_marks[l:idx])
endfunction

function! HarpoonNext()
  if empty(g:harpoon_marks) | echo "Harpoon list is empty" | return | endif
  let l:file = expand('%:p')
  let l:idx = index(g:harpoon_marks, l:file)
  let l:next = (l:idx + 1) % len(g:harpoon_marks)
  execute 'edit ' . fnameescape(g:harpoon_marks[l:next])
endfunction

function! HarpoonPrev()
  if empty(g:harpoon_marks) | echo "Harpoon list is empty" | return | endif
  let l:file = expand('%:p')
  let l:idx = index(g:harpoon_marks, l:file)
  let l:prev = (l:idx - 1 + len(g:harpoon_marks)) % len(g:harpoon_marks)
  execute 'edit ' . fnameescape(g:harpoon_marks[l:prev])
endfunction
function! HarpoonFuzzy()
  if empty(g:harpoon_marks) | echo "Harpoon list is empty" | return | endif
  let l:lines = []
  for i in range(len(g:harpoon_marks))
    let l:short = fnamemodify(g:harpoon_marks[i], ':~:.')
    call add(l:lines, (i + 1) . '  ' . l:short)
  endfor
  call fzf#run(fzf#wrap({
    \ 'source':  l:lines,
    \ 'sink*':   function('s:HarpoonFzfSink'),
    \ 'options': ['--prompt=Harpoon> ', '--ansi',
    \             '--layout=reverse-list', '--border=rounded',
    \             '--color=prompt:#f38ba8,pointer:#cba6f7',
    \             '--no-preview',
    \             '--expect=ctrl-d'],
    \ 'window': {'width': 0.5, 'height': 0.5, 'yoffset': 0.5, 'xoffset': 0.5}
    \ }))
endfunction

function! s:HarpoonFzfSink(lines) abort
  if len(a:lines) < 2 | return | endif
  let l:key  = a:lines[0]
  let l:line = a:lines[1]
  let l:idx  = str2nr(split(l:line, '\s\+')[0]) - 1

  if l:key == 'ctrl-d'
    let l:removed = fnamemodify(g:harpoon_marks[l:idx], ':t')
    call remove(g:harpoon_marks, l:idx)
    call HarpoonSave()
    echo "Removed: " . l:removed
  else
    execute 'edit ' . fnameescape(g:harpoon_marks[l:idx])
  endif
endfunction
" ── Persistence ─────────────────────────────────────────────────────────────
let g:harpoon_file = expand('~/.vim/harpoon_marks.json')

function! HarpoonSave()
  call writefile([json_encode(g:harpoon_marks)], g:harpoon_file)
endfunction

function! HarpoonLoad()
  if filereadable(g:harpoon_file)
    let l:raw = readfile(g:harpoon_file)
    if !empty(l:raw)
      let g:harpoon_marks = json_decode(l:raw[0])
    endif
  endif
endfunction

autocmd VimEnter * call HarpoonLoad()
autocmd VimLeave * call HarpoonSave()

" ── Keymaps ─────────────────────────────────────────────────────────────────
nnoremap <leader>a  :call HarpoonAdd()<CR>
nnoremap <leader>d  :call HarpoonRemove()<CR>
" <leader>D, not <leader>dd: that made <leader>d wait for a second key
nnoremap <leader>D  :call HarpoonRemoveAll()<CR>
nnoremap <leader>1  :call HarpoonJump(1)<CR>
nnoremap <leader>2  :call HarpoonJump(2)<CR>
nnoremap <leader>3  :call HarpoonJump(3)<CR>
nnoremap <leader>4  :call HarpoonJump(4)<CR>
nnoremap <leader>5  :call HarpoonJump(5)<CR>
nnoremap <leader>6  :call HarpoonJump(6)<CR>
nnoremap <leader>7  :call HarpoonJump(7)<CR>
nnoremap <leader>8  :call HarpoonJump(8)<CR>
nnoremap <leader>9  :call HarpoonJump(9)<CR>
nnoremap <leader>n  :call HarpoonNext()<CR>
nnoremap <leader>p  :call HarpoonPrev()<CR>
nnoremap <leader>h  :call HarpoonFuzzy()<CR>
