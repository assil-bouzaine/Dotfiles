" Vim's built-in Markdown syntax conceals emphasis, but not inline backticks.
" Extend only inline code; fenced blocks keep their language labels visible.
if !has('conceal') || !get(g:, 'markdown_syntax_conceal', 1)
  finish
endif

syntax region markdownCode matchgroup=markdownCodeDelimiter start="\%(`\)\@<!`\%(`\)\@!" end="\%(`\)\@<!`\%(`\)\@!"
      \ keepend oneline concealends contains=markdownLineStart
syntax region markdownCode matchgroup=markdownCodeDelimiter start="\%(`\)\@<!``\%(`\)\@! \=" end=" \=\%(`\)\@<!``\%(`\)\@!"
      \ keepend oneline concealends contains=markdownLineStart
