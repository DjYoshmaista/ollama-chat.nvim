# ollama-chat.nvim

Ollama neovim inline chat plugin. Provides a chat interface and interactive session with ollama from within neovim in a simplistic and easily configured presentation.

## Installation

Use your favorite plugin manager to install `ollama-chat.nvim`.

For example, with `packer.nvim`:

```lua
use {
  'yosh/ollama-chat.nvim',
  requires = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('ollama_chat').setup()
  end
}
```

## Configuration

The plugin comes with a default configuration that should work out of the box. You can override the default configuration by passing a table to the `setup` function.

For example:

```lua
require('ollama_chat').setup({
  -- your custom configuration
})
```

For a full list of configuration options, please see the `default_config.json` file.

## Usage

The plugin provides the following commands:

- `:OllamaChat` - Opens the chat window.
- `:OllamaChatSend` - Sends the input from the input window to the Ollama API.
- `:OllamaChatBuffer` - Sends the content of the current buffer to the Ollama API.
- `:OllamaChatLog` - Opens the log file.

The plugin also provides the following keymaps:

- `<leader>0` - Opens the chat window.
- `<leader>0s` - Sends the input from the input window to the Ollama API.
- `<leader>0b` - Sends the content of the current buffer to the Ollama API.
- `<leader>0l` - Opens the log file.