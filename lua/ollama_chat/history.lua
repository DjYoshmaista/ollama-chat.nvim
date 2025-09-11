-- history.lua - History management and persistence for nvim-ollama-chat: Handles saving chat sessions to disk in various formats (markdown, json, txt) in an organized directory

local Path = require("plenary.path")
local json = require("plenary.json")
local config_module = require("ollama_chat.config")

local M = {}

-- Formats the session messages into a Markdown string
--  @param messages table - The Llist of message objects
--  @return string - The formatted Markdown content
local function format_as_markdown(messages)
	local lines = {
		"# Ollama Chat Session: " .. os.date("%Y-%m-%d %H:%M:%S"),
		"",
	}
	for _, msg in ipairs(messages) do
		table.insert(lines, string.format("**%s:**", string.upper(msg.role)))
		table.insert(lines, "")
		table.insert(lines, msg.content)
		table.insert(lines, "")
		table.insert(lines, "---")
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

-- Formats the session messages into a JSON string
--  @param messages table - The list of message objects
--  @return string|nil - The formatted JSON string, or nil on error
local function format_as_json(messages)
	local ok, encoded = pcall(json.encode, messages, { pretty = true })
	if ok then
		return encoded
	end
	-- TODO: Logging the error with the logger module
	return nil
end

-- Formats the session messages into a plain text string
--  @param messages table - The list of message objects
--  @return string - The formatted plain text document
local function format_as_text(messages)
	local lines = {}
	for _, msg in ipairs(messages) do
		table.insert(lines, string.format("--- %s ---", string.upper(msg.role)))
		table.insert(lines, msg.content)
		table.insert(lines, "")
	end
	return table.concat(lines, "\n")
end

-- Determines the next sequential chat filename
--  @param dir_path Path - The directory to scan
--  @param format string - The file extension
--  @return string - The full path for the new chat file
local function get_next_chat_filepath(dir_path, format)
	local max_num = 0
	-- Ensure dir exists before scanning
	dir_path:mkdirp()

	for _, file in ipairs(dir_path:scandir()) do
		local filename = file:match("([^/]+)$")
		local num = tonumber(filename:match("^chat_($d+)." .. format .. "$"))
		if num and num > max_num then
			max_num = num
		end
	end

	local next_num = max_num + 1
	local new_filename = string.format("chat_%03d.%s", next_num, format)
	return dir_path:joinpath(new_filename)
end

-- Public function to save a chat session
--  @param session_messages table - The list of message objects from the completed chat
function M.save_chat(session_messages)
	local config = config_module.get_config().chat_history
	if not config.enabled then
		return
	end

	-- Don't save empty or initial system-only message sessions
	if not session_messages or #session_messages <= 1 then
		return
	end

	-- Determine content based on format
	local content
	if config.format == "md" then
		content = format_as_markdown(session_messages)
	elseif config.format == "json" then
		content = format_as_json(session_messages)
	elseif config.format == "txt" then
		content = format_as_text(session_messages)
	else
		vim.notify("OllamaChat: Invalid history format configured: " .. config.format, vim.log.levels.ERROR)
		return
	end

	if not content then
		vim.notify("OllamaChat: Failed to format chat history.", vim.log.levels.ERROR)
		return
	end

	-- Determine file path
	local base_path = Path:new(config.path)
	local year = os.date("%Y")
	local month = os.date("%m_%B")
	local target_dir = base_path:joinpath(year, month)

	local filepath = get_next_chat_filepath(target_dir, config.format)

	-- Write the file
	local success, err = pcall(function()
		filepath:write(content, "w")
	end)

	if not success then
		vim.notify("OllamaChat: Failed to save chat history - " .. tostring(err), vim.log.levels.Error)
	end
end

return M
