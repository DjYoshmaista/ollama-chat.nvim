" ollama_chat.vim - Plugin entry point
if exists('g:loaded_ollama_chat')
	finish
endif

let g:loaded_ollama_chat = 1

" Command definitions
command! OllamaChat lua require('ollama_chat').open_chat()

" Key bindings
nnoremap <leader>oc :OllamaChat<CR>

" Autocommands for setup
autocmd VimEnter * lua require('ollama_chat').setup()
