-- init.lua - Main Plugin Initialization
local M = {}

function M.setup(config)
	-- Add a diagnostic check for plenary
	if not pcall(require, "plenary") then
		vim.notify(
			"OllamaChat Error: plenary.nvim is required. Please ensure 'nvim-lua/plenary.nvim' is installed and loaded.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Load configuration
	local config_manager = require("ollama_chat.config")
	config_manager.setup(config)
	local cfg = config_manager.get_config()

	-- Setup logger
	require("ollama_chat.logger").setup(cfg.logging)

	-- Load other modules
	require("ollama_chat.client")
	require("ollama_chat.chat")

	-- Log successful initialization
	require("ollama_chat.logger").info("Ollama Chat plugin initialized!")
end

function M.open_chat()
	require("ollama_chat.logger").info("Opening chat from command")
	require("ollama_chat.chat").open()
end

function M.send_input()
	require("ollama_chat.logger").info("Sending input from command")
	require("ollama_chat.chat").send_input()
end

return M
