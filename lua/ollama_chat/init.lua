-- init.lua - Main Plugin Initialization
local M = {}

function M.setup(config)
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

return M
