-- init.lua - Main Plugin Initialization
local M = {}

function M.setup(config)
	-- Add a diagnostic check for plenary
	if not vim.json then
		vim.notify(
			"OllamaChat Error: Failed to load plenary.json. Please ensure 'nvim-lua/plenary.nvim' is installed and loaded.",
			vim.log.levels.ERROR
		)
		return
	end
	local Path = require("plenary.path")
	if not Path then
		vim.notify(
			"OllamaChat Error: Error loading plenary.path.  Please ensure 'nvim-lua/plenary.vim' is installed and loaded.",
			vim.log.levels.ERROR
		)
		return
	end
	M.Path = Path

	-- Load configuration
	local config_manager = require("ollama_chat.config")
	config_manager.setup(config)
	local cfg = config_manager.get_config()

	require("ollama_chat.logger").setup(cfg.logging)

	require("ollama_chat.client")
	require("ollama_chat.chat")

	-- Log successful attempt
	require("ollama_chat.logger").info("Ollama Chat plugin initialized!")
end

function M.open_chat()
	require("ollama_chat.chat").open()
end

function M.send_input()
	require("ollama_chat.chat").send_input()
end

return M
