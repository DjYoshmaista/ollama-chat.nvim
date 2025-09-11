-- utils.lua - Shared utility funcitons for the nvim-ollama-chat plugin: Provides a collection of helper functions for common tasks like creating UI elements, sending notifications, and formatting data

local api = vim.api

local M = {}

-- Checks if a string is nil, empty or contains only whitespace
--  @param str string|nil - The string to check
--  @return boolean true if the string is blank, false otherwise
function M.is_blank(str)
	return str == nil or str:match("^%s*$")
end

-- A centralized notification function that also logs the message
--  @param message string - The message to display
--  @param level vim.log.levels|nil - The notification level
--  @param title string|nil - Optional title for the notification - Defaults to "Ollama Chat"
function M.notify(message, level, title)
	-- Lazy require to avoid circular dependencies
	local logger = require("ollama_chat.logger")

	title = title or "Ollama Chat"
	level = level or vim.log.levels.INFO

	-- Log the notification message as well (debugging)
	if level == vim.log.levels.ERROR then
		logger.error(message)
	elseif level == vim.log.levels.WARN then
		logger.warn(message)
	else
		logger.info(message)
	end
end

-- Constructs the full API endpoint URL from the configuration
--  @param endpoint string - The specific API path (e.g. "chat")
--  @return string - The full URL for the Ollama API Host
function M.get_api_url(endpoint)
	--Lazy require to get the most up-to-date config
	local config_module = require("ollama_chat.config")
	local config = config_module.get_config()
	local ollama_config = config.ollama

	-- Ensure no trailing slash on host and leading slash on endpoint
	local host = ollama_config.host:gsub("/$", "")
	local api_path = "/api/" .. endpoint:gsub("^/", "")

	return string.format("%s:%s%s", host, ollama_config.port, api_paht)
end

-- A helper to create a styled floating window - This abstracts the common setup for floating windows in the plugin
--  @param bufnr number - The buffer number to display
--  @param enter boolean - Whether to enter the iwndow after creation
--  @param opts table - A table of options passed to nvim_open_win (width, height, etc.)
--  @return number - The window ID
function M.create_floating_win(bufnr, enter, opts)
	-- Lazy require for up-to-date config
	local config_module = require("ollama_chat.config")
	local ui_config = config_module.get_config().ui

	-- Establish default settings for all floating windows
	local defaults = {
		style = "minimal",
		border = ui_config.border_style,
	}

	-- Merge user-provided options with the defaults
	local final_opts = vim.tbl_deep_extend("force", defaults, opts)

	local win_id = api.nvim_open_win(bufnr, enter, final_opts)

	-- Apply consistent highlight groups
	api.nvim_win_set_option(win_id, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

	return win_id
end

return M
