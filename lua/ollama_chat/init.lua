-- init.lua - Main Plugin Initialization
local M = {}

function M.setup(config)
	-- Add a diagnostic check for plenary
	local plenary_ok, json = pcall(require, "plenary.json")
	if not plenary_ok or not json then
		vim.notify(
			"OllamaChat Error: Failed to load plenary.json. Please ensure 'nvim-lua/plenary.nvim' is installed and loaded.",
			vim.log.levels.ERROR
		)
	end

	-- Init logging system
	require("ollama_chat.logger").setup()

	-- Load configuration
	local config_manager = require("ollama_chat.config")
	config_manager.setup(config)
	local cfg = config_manager.get_config()

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
