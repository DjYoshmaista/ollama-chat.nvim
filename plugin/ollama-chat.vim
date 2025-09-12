if exists('g:loaded_ollama_chat') | finish | endif

let g:loaded_ollama_chat = 1

command! OllamaChat lua require('ollama_chat').open_chat()
command! OllamaChatSend lua require('ollama_chat').send_input()
command! OllamaChatLog lua require('plenary.path'):new(vim.fn.stdpath('data'), 'ollama_chat', 'logs', 'ollama_chat.log'):open()

nnoremap <leader>0 :OllamaChat<CR>
nnoremap <leader>0s :OllamaChatSend<CR>
nnoremap <leader>0l :OllamaChatLog<CR>
