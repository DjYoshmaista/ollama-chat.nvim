-- logger.lua - A simple file-based logger for nvim-ollama-chat plugin: Provides a centralized method of logging messages at different severity levels (controlled by the plugin's configuration).  This is essential for debugging async operations and plugin behavior

local Path = require("plenary.path")
local config_module = require("ollama_chat.config")

local M = {}

-- Map string levels to numerical priorities.  Higher number = more verbose
local log_levels = {
	EXCEPT = 1,
	ERROR = 2,
	CRITICAL = 3,
	WARN = 4,
	INFO = 5,
	DEBUG = 6,
}

-- Internal state for the logger
local state = {
	is_enabled = false,
	log_level_num = log_levels.ERROR, -- Default to least verbose
	log_file_path = nil,
}

-- Writes a formatted message to the ocnfigured log file
--  @param level_str string - The string representation of the level (e.g. "INFO")
--  @param message any - The message to log - Will be converted to a string
local function write_to_log(level_str, message)
	if not state.is_enabled or not state.log_file_path then
		return
	end

	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	-- Use tostring() to handle non-string messages gracefully
	local formatted_message = string.format("[%s] [%s] - %s\n", timestamp, level_str, tostring(message))

	-- Use a protected call for file I/O to prevent errors from crashing the plugin
	local succes, err = pcall(function()
		-- The 'a' flag appends to the file if it exists, or creates it if it doesn't
		state.log_file_path:write(formatted_message, "a")
	end)

	if not success then
		vim.notify("OllamaClient Logger: Failed to write to log file: " .. tostring(err), vim.log_levels.ERROR)
		state.is_enabled = false -- Disable logger to prevent repeated errors
	end
end

-- Configures and initializes the logger based on the user's settings - This should be called once when the plugin is loaded
function M.setup()
	-- Use protected call to avoid errors if config is malformed
	local ok, config = pcall(config_module.get_config)
	if not ok then
		-- Silently fail - Logger remains disabled
		return
	elseif not config.logging then
		vim.notify(
			"OllamaClient Logger: Logging not configured and/or not enabled: " .. tostring(err),
			vim.log_levels.ERROR
		)
		return
	end

	local logging_config = config.logging
	state.is_enabled = logging_config.enabled
	state.log_level_num = log_levels[string.upper(logging_config.level)] or log_levels.INFO

	if state.is_enabled then
		state.log_file_path = Path:new(logging_config.filepath)
		-- Ensure the dir for the log file exists
		local parent_dir = state.log_file_path:parent()
		if not parent_dir:exists() then
			parent_dir:mkdirp()
		end
	end
end

-- Logs a message with DEBUG severity
--  @param message any - The message to log
function M.debug(message)
	if state.log_level_num >= log_levels.DEBUG then
		write_to_log("DEBUG", message)
	end
end

-- Logs a message with INFO severity
--  @param message any - Message to log
function M.info(message)
	if state.log_level_num >= log_levels.INFO then
		write_to_log("INFO", message)
	end
end

-- Logs a message with WARN severity
--  @param message any - Message to log
function M.warn(message)
	if state.log_level_num >= log_levels.WARN then
		write_to_log("WARNING", message)
	end
end

-- Logs a message with CRITICAL severity
--  @param message any - Message to log
function M.critical(message)
	if state.log_level_num >= log_levels.CRITICAL then
		write_to_log("CRITICAL", message)
	end
end

-- Logs a message with ERROR severity
--  @param message any - Message to log
function M.error(message)
	if state.log_level_num >= log_levels.ERROR then
		write_to_log("ERROR", message)
	end
end

-- Logs a message with EXCEPTION severity
--  @param message any - Message to log
function M.except(message)
	if state.log_level_num >= log_levels.EXCEPT then
		write_to_log("EXCEPTION", message)
	end
end

return M
