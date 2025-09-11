-- config.lua
-- Handles configuration loading

local Path = require("plenary.path")
local json = require("plenary.json")

local M = {}

-- Suppoorted config formats: JSON, YAML, Python-like
-- Holds the merged, final configuration - initialized with some defaults in case setup() isn't called
local config = {
	ollama_host = "0.0.0.0",
	ollama_port = 11434,
	default_model = "qwen3:8b",
	chat_history = {
		enabled = true,
		path = vim.fn.stdpath("data") .. "/ollama_chat/chats",
		format = "md", -- md, json or txt
	},
	logging = {
		enabled = true,
		level = "INFO", -- DEBUG, INFO, WARN, CRITICAL, ERROR, EXCEPT
		path = vim.fn.stdpath("data") .. "/ollama_chat/ollama_chat.log",
	},
	ui = {
		chat_win_width = 80,
		show_icons = true,
		border_style = "rounded", -- rounded, single, double, solid
	},
}

-- Deeply merge two tables - values in 't2' will overwrite the values in 't1'
-- @param t1 table the base table; @param t2 table the table to merge in; @return table the merged table
local function deep_merge(t1, t2)
	for k, v in pairs(t2) do
		if type(v) == "table" and type(t1[k]) == "table" then
			t1[k] = deep_merge(t1[k], v)
		else
			t1[k] = v
		end
	end
	return t1
end

-- Validates the configuration against a schema
-- @param conf table -- The configuration table to validate
-- @return boolean, string|nil True if valid, false and an error message if not
local function validate_config(conf)
	-- TODO: Implement schema validation
	-- Could involve checking for required keys, correct value types, and valid enum values (log levels, history formats, etc), assumes config is valid currently
	if not conf.ollama_host or type(conf.ollama_host) ~= "string" then
		return false, "Invalid or missing 'ollama_host'"
	end
	if not conf.ollama_port or type(conf.ollama_port) ~= "number" then
		return false, "Invalid or missing 'ollama_port'"
	end
	return true, nil
end

-- Main setup function for the plugin -- This is what users will call from init.lua.  Merges the default config with the user's provided options
-- @param user_opts table User-provided configuration options
function M.setup(user_opts)
	user_opts = user_opts or {}
	config = deep_merge(config, user_opts)

	local is_valid, err = validate_config(config)
	if not is_valid then
		vim.notify("OllamaChat: Invalid configuration - " .. err, vim.log.levels.ERROR)
		return
	end

	vim.notify("OllamaChat: Configuration loaded successfully.", vim.log.levels.INFO)
end

-- Returns the current configuration table
-- @return table The current config
function M.get_config()
	return config
end

-- Saves the current config to the user's config file
-- Only necessary if config is not managed via dotfiles
-- @param new_config table The configuration table to save
function M.save_config(new_config)
	-- Path should point to where user-specific overrides are stored
	local user_config_path = Path:new(vim.fn.stdpath("config"), "user_config.json")

	-- Ensure the dir exists
	user_config_path:dir():mkdirp()

	local success, err = pcall(function()
		local config_string = json.encode(new_config, { pretty = true })
		user_config_path:write(config_string, "w")
	end)

	if success then
		-- Also update currently running config
		config = new_config
		vim.notify("OllamaChat: Configuration saved to " .. tostring(user_config_path))
	else
		vim.notify("OllamaChat: Failed to save configuration " .. err, vim.log.levels.ERROR)
	end
end

return M
