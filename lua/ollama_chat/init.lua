-- init.lua - Main Plugin Initialization
local M = {}

function M.setup(config)
	-- Init logging system
	require("ollama-chat.logger").setup()

	-- Load configuration
	local config_manager = require("ollama_chat.config")
	local cfg = config_manager.load_config(config)

	-- Initialize components
	require("ollama_chat.client").setup(cfg.ollama)
	require("ollama_chat.history").setup(cfg.history)

	-- Setup UI components
	require("ollama_chat.chat").setup(cfg.ui)

	-- Log successful attempt
	require("ollama_chat.logger").info("Ollama Chat plugin initialized!")
end

return M
