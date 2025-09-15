-- config.lua
-- Handles configuration loading

local Path = require("plenary.path")
local M = {}
local cached_config = nil

-- Suppoorted config formats: JSON, YAML, Python-like
-- Holds the merged, final configuration - initialized with some defaults in case setup() isn't called
local config = {
	ollama_host = "0.0.0.0",
	ollama_port = 11434,
	default_model = "qwen3:8b",
	chat_history = {
		enabled = true,
		path = "/home/yosh/ollama_chat.log",
		format = "md", -- md, json or txt
	},
	log = {
		enabled = true,
		level = "DEBUG", -- DEBUG, INFO, WARN, CRITICAL, ERROR, EXCEPT
		path = "/home/yosh/ollama_chat_debug.log",
	},
	ui = {
		-- Main chat window configuration
		chat_win_width = 80,
		chat_win_height = 20,
		chat_win_pos = "center", -- "center", "top", "bottom", or { row = N, col = N }

		-- Input window configuration
		input_win_height = 3,
		input_win_width = nil, --nil means match chat window width

		-- Window behavior
		start_in_insert_mode = true,
		auto_scroll = true,

		-- Layout options
		layout = "vertical", -- "vertical" (input below chat), "horizontal" (side-by-side)

		-- Various options
		show_icons = true,
		border_style = "rounded", -- rounded, single, double, solid
	},
}

function M.invalidate_cache()
	cached_config = nil
end

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

local config_schema = {
	ollama_host = { type = "string", required = true },
	ollama_port = { type = "number", required = true },
	default_model = { type = "string", required = true },
	chat_history = {
		type = "table",
		fields = {
			enabled = { type = "boolean", required = true },
			path = { type = "string", required = true },
			format = { type = "string", required = true, enum = { "md", "json", "txt" } },
		},
	},
}

local function validate_against_schema(conf, schema, path)
	path = path or ""
	for key, rules in pairs(schema) do
		local value = conf[key]
		-- TODO: Validation logic using schema
	end
end

-- Validates the configuration against a schema
-- @param conf table -- The configuration table to validate
-- @return boolean, string|nil True if valid, false and an error message if not
local function validate_config(conf)
	-- TODO: Implement schema validation
	-- Could involve checking for required keys, correct value types, and valid enum values (log levels, history formats, etc), assumes config is valid currently

	-- Validate top-level keys
	if not conf.ollama_host or type(conf.ollama_host) ~= "string" then
		return false, "Invalid or missing 'ollama_host'"
	end
	if not conf.ollama_port or type(conf.ollama_port) ~= "number" then
		return false, "Invalid or missing 'ollama_port'"
	end
	if not conf.default_model or type(conf.default_model) ~= "string" then
		return false, "Invalid or missing 'default_model'"
	end

	-- Validate chat_history
	if conf.chat_history.enabled == nil or type(conf.chat_history.enabled) ~= "boolean" then
		return false, "Invalid or missing key or key type for 'chat_history' for key 'enabled'"
	end
	if not conf.chat_history.path or type(conf.chat_history.path) ~= "string" then
		return false, "Invalid or missing value for 'chat_history' entry 'path'"
	end
	if not conf.chat_history.format or type(conf.chat_history.format) ~= "string" then
		return false, "Invalid or missing value for 'chat_history' entry 'format'"
	end

	-- Validate logging
	if not conf.log.enabled or type(conf.log.enabled) ~= "boolean" then
		return false, "Invalid or missing value for 'logging' entry 'enabled'"
	end
	if not conf.log.level or type(conf.log.level) ~= "string" then
		return false, "Invalid or missing value for 'logging' entry 'level'"
	end
	if not conf.log.path or type(conf.log.path) ~= "string" then
		return false, "Invalid or missing value for 'logging' entry 'path'"
	end

	-- Validate UI
	if not conf.ui.chat_win_width or type(conf.ui.chat_win_width) ~= "number" then
		return false, "Invalid or missing value for 'ui' entry 'chat_win_width'"
	end
	if not conf.ui.chat_win_height or type(conf.ui.chat_win_height) ~= "number" then
		return false, "Invalid or missing value for 'ui' entry 'chat_win_height'"
	end
	if not conf.ui.input_win_height or type(conf.ui.input_win_height) ~= "number" then
		return false, "Invalid or missing value for 'ui' entry 'input_win_height'"
	end
	if not conf.ui.input_win_width or type(conf.ui.input_win_width) ~= "number" then
		return false, "Invalid or missing value for 'ui' entry 'input_win_width'"
	end
	if not conf.ui.border_style or type(conf.ui.border_style) ~= "string" then
		return false, "Invalid or missing value for 'ui' entry 'border_style'"
	end

	-- Validate position
	if conf.ui.chat_win_position then
		local pos = conf.ui.chat_win_pos
		if type(pos) == "string" then
			local valid_positions = { center = true, top = true, bottom = true }
			if not valid_positions[pos] then
				return false, "Invalid position string.  Must be 'center', 'top' or 'bottom'"
			end
		elseif type(pos) == "table" then
			if type(pos.row) ~= "number" or type(pos.col) ~= "number" then
				return false, "Invalid position table.  Must have numeric 'row' and 'col' fields"
			end
		else
			return false, "Invalid position type.  Must be string or table"
		end
	end

	return true, nil
end

-- Main setup function for the plugin -- This is what users will call from init.lua.  Merges the default config with the user's provided options
-- @param user_opts table User-provided configuration options
function M.setup(user_opts)
	user_opts = user_opts or {}

	-- Handle nested 'ollama' configuration from user's config file
	if user_opts.ollama then
		local ollama = user_opts.ollama
		if ollama.server and type(ollama.server) == "table" then
			config.ollama_host = ollama.server.host or config.ollama_host
			config.ollama_port = ollama.server.port or config.ollama_port
		end
		config.default_model = ollama.model or config.default_model
		-- TODO: Extract hyperparameters and set default values
	end

	-- Handle nested 'history' configuration
	if user_opts.history then
		local history = user_opts.history
		if history.save_format then
			-- Only one format supported for now.  Current action - take the first
			if type(history.save_format) == "table" and #history.save_format > 0 then
				config.chat_history.format = history.save_format[1]
			elseif type(history.save_format) == "string" then
				config.chat_history.format = history.save_format
			end
		end
		if history.storage_path then
			config.chat_history.path = history.storage_path
		end
	end

	-- Handle nested 'ui' configuration
	if user_opts.ui then
		local ui = user_opts.ui

		-- Window dimensions
		if ui.window_width then
			config.ui.chat_win_width = ui.window_width
		end
		if ui.window_height then
			config.ui.chat_win_height = ui.window_height
		end
		if ui.chat_win_width then
			config.ui.chat_win_width = ui.chat_win_width
		end
		if ui.chat_win_height then
			config.ui.chat_win_height = ui.chat_win_height
		end
		if ui.input_win_width then
			config.ui.input_win_width = ui.input_win_width
		end
		if ui.input_win_height then
			config.ui.input_win_height = ui.input_win_height
		end

		-- Window positioning and layout
		if ui.position then
			config.ui.chat_win_position = ui.position
		end
		if ui.chat_win_pos then
			config.ui.chat_win_pos = ui.chat_win_pos
		end
		if ui.layout then
			config.ui.layout = ui.layout
		end
		if ui.window_gap ~= nil then
			config.ui.window_gap = ui.window_gap
		end

		-- Styling options
		if ui.border_style then
			config.ui.border_style = ui.border_style
		end
		if ui.show_icons ~= nil then
			config.ui.show_icons = ui.show_icons
		end

		-- Behavior options
		if ui.start_in_insert_mode ~= nil then
			config.ui.start_in_insert_mode = ui.start_in_insert_mode
		end
		if ui.auto_scroll ~= nil then
			config.ui.auto_scroll = ui.auto_scroll
		end
	end

	-- Handle nested 'logging' configuration
	if user_opts.log then
		local log = user_opts.log
		if log.level then
			config.log.level = string.upper(log.level) -- Ensure uppercase
		end
		if log.path then
			config.log.path = log.path
		end
	end

	-- Merge any other direct top-level settings
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
	if not cached_config then
		cached_config = config
	end
	return cached_config
end

-- Saves the current config to the user's config file
-- Only necessary if config is not managed via dotfiles
-- @param new_config table The configuration table to save
function M.save_config(new_config)
	-- Path should point to where user-specific overrides are stored
	local user_config_path = Path:new(vim.fn.stdpath("config"), "user_config.json")

	-- Ensure the dir exists
	user_config_path:dir():mkdir({ parents = true })

	local success, err = pcall(function()
		local config_string = vim.json.encode(new_config, { pretty = true })
		user_config_path:write(config_string, "w")
	end)

	if success then
		-- Also update currently running config
		config = new_config
		vim.notify("OllamaChat: Configuration saved to " .. tostring(user_config_path), vim.log.levels.INFO)
	else
		vim.notify("OllamaChat: Failed to save configuration " .. err, vim.log.levels.ERROR)
	end
end

return M
