-- chat.lua - Chat interface logic for nvim-ollam-chat
-- 	Manages creation, interaction and destruction of the chat UI, including the chat history window and the user input buffer

local api = vim.api
local config_module = require("ollama_chat.config")
local client = require("ollama_chat.client")
local logger = require("ollama_chat.logger")

logger.info("Ollama chat plugin initialized!")

local M = {}

logger.info("Ollama 'M' module initialized")

-- Internal state to manage UI elements and conversation history
local state = {
	chat_buf = nil,
	chat_win = nil,
	input_buf = nil,
	input_win = nil,
	session_messages = {}, -- Stores { role = "...", content = "..." }
	is_thinking = false, -- Prevents sending new messages while waiting for a response
	assistant_response_started = false,
}
logger.info("Ollama state table initialized")

-- Safely closes windows and deletes buffers
local function close_chat_windows()
	if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
		api.nvim_win_close(state.chat_win, true)
		logger.info("Ollama state 'chat_win' closed")
	end
	if state.input_win and api.nvim_win_is_valid(state.input_win) then
		api.nvim_win_close(state.input_win, true)
		logger.info("Ollama state 'input_win' closed")
	end
	if state.chat_buf and api.nvim_buf_is_valid(state.chat_buf) then
		api.nvim_buf_delete(state.chat_buf, { force = true })
		logger.info("Ollama state 'chat_buf' closed")
	end
	if state.input_buf and api.nvim_buf_is_valid(state.input_buf) then
		api.nvim_buf_delete(state.input_buf, { force = true })
		logger.info("Ollama stat 'input_buf' closed")
	end

	-- Reset state
	state.chat_buf = nil
	state.chat_win = nil
	state.input_buf = nil
	state.input_win = nil
	state.session_messages = {}
	state.is_thinking = false
	state.assistant_response_started = false
	logger.info("Ollama states reset.  Chat window closed.")
end

-- Appends a message to the chat buffer
--  @param role string "user" or "assistant"
--  @param content string - The message content
local function render_message(role, content)
	logger.info("Appending message to the chat buffer.  Message: " .. content)
	vim.schedule(function()
		if not (state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)) then
			logger.info("State chat_buf or nvim_buf_is_valid not true.")
			return
		end

		api.nvim_buf_set_option(state.chat_buf, "modifiable", true)
		logger.info("State 'chat_buf' set to 'modifiable'")

		local header = string.format("--- %s ---", string.upper(role))
		local lines = vim.split(content, "\n")

		-- Add a blank line for spacing if buffer is not empty
		if api.nvim_buf_line_count(state.chat_buf) > 1 then
			api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { "" })
			logger.debug("Added blank line to chat_buf")
		end

		api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { header })
		logger.debug("chat_buf state changed.  Current value: " .. header)
		api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, lines)
		logger.debug("Added content lines to chat_buf")
		api.nvim_buf_set_option(state.chat_buf, "modifiable", false)
		logger.debug("chat_buf set to non-modifiable")

		-- Auto-scroll to the bottom
		if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
			api.nvim_win_set_cursor(state.chat_win, { api.nvim_buf_line_count(state.chat_buf), 0 })
		end
	end)
end

function M.set_model(model_name)
	if not model_name then
		-- Show model selector
		local models = client.get_available_models(function(models)
			vim.ui.select(models, {
				prompt = "Select Ollama model:",
			}, function(choice)
				if choice then
					state.current_model = choice
					render_message("system", "Switched to model: " .. choice)
				end
			end)
		end)
	else
		state.current_model = model_name
	end
end

-- Appends a streaming chunk of context to the last message in the chat buffer
-- 	@param chunk string - The content chunk from the stream
local function render_stream_chunk(chunk)
	logger.info("render_stream_chunk called with '" .. chunk .. "'")
	vim.schedule(function()
		if not (state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)) then
			logger.error("Chat buffer invalid when trying to render the stream chunk")
			return
		end

		api.nvim_buf_set_option(state.chat_buf, "modifiable", true)

		-- Get the last line of the buffer
		local last_line_idx = api.nvim_buf_line_count(state.chat_buf) - 1
		local last_line = api.nvim_buf_get_lines(state.chat_buf, last_line_idx, -1, false)[1] or ""

		-- Append the new chunk to the last line
		local new_content = last_line .. chunk
		local new_lines = vim.split(new_content, "\n")

		api.nvim_buf_set_lines(state.chat_buf, last_line_idx, -1, false, new_lines)
		api.nvim_buf_set_option(state.chat_buf, "modifiable", false)

		-- Auto-scroll
		if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
			api.nvim_win_set_cursor(state.chat_win, { api.nvim_buf_line_count(state.chat_buf), 0 })
		end
	end)
end

-- Retrieves user input and sends it to client then handles the response
local function send_current_input()
	if state.is_thinking then
		logger.warn("Already thinking, ignoring input")
		return
	end

	local input_lines = api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
	local prompt = table.concat(input_lines, "\n")

	if prompt:gsub("%s", "") == "" then
		logger.info("Empty prompt, ignoring")
		return
	end

	logger.info("Sending input: " .. prompt)

	-- Clear input buffer
	api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

	-- Add user message to history and render it
	table.insert(state.session_messages, { role = "user", content = prompt })
	render_message("user", prompt)

	-- Set thinking state
	state.is_thinking = true
	state.assistant_response_started = false
	logger.info("Set is_thinking to true")

	-- Prepare for assistant's response
	vim.schedule(function()
		if state.chat_buf and api.nvim_buf_is_valid(state.chat_buf) then
			api.nvim_buf_set_option(state.chat_buf, "modifiable", true)
			api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { "", "--- ASSISTANT ---", "" })
			api.nvim_buf_set_option(state.chat_buf, "modifiable", false)
			logger.info("Added ASSISTANT header to chat buffer")
		end
	end)

	local assistant_response_content = ""

	-- Add error handling wrapper
	local function safe_callback(callback_name, callback_func)
		return function(...)
			local success, err = pcall(callback_func, ...)
			if not success then
				logger.error("Error in " .. callback_name .. ": " .. tostring(err))
				state.is_thinking = false
				render_message("error", "Error in " .. callback_name .. ": " .. tostring(err))
			end
		end
	end

	client.stream_chat({
		model = config_module.get_config().default_model,
		messages = state.session_messages,
		on_chunk = safe_callback("on_chunk", function(chunk)
			logger.info("on_chunk called with: '" .. chunk .. "'")

			-- Clean chunk and render
			local clean_chunk = chunk
			if chunk:match("^</?think>") then
				logger.debug("Filtering out think tag: " .. chunk)
				clean_chunk = chunk:gsub("</?think>", "")
			end

			if clean_chunk ~= "" then
				logger.info("Rendering clean chunk: '" .. clean_chunk .. "'")
				render_stream_chunk(clean_chunk)
				assistant_response_content = assistant_response_content .. clean_chunk
				state.assistant_response_started = true
			else
				logger.debug("Skipping empty chunk after cleaning")
			end
		end),
		on_finish = safe_callback("on_finish", function(response)
			logger.info("Stream finished. Full response length: " .. #assistant_response_content)

			-- Only add to session messages if we got content
			if assistant_response_content ~= "" then
				table.insert(state.session_messages, { role = "assistant", content = assistant_response_content })
				logger.info("Added assistant response to session messages")
			else
				logger.warn("No assistant content received")
			end

			-- Reset thinking state
			state.is_thinking = false
			state.assistant_response_started = false
			logger.info("Reset is_thinking to false - ready for next input")
		end),
		on_error = safe_callback("on_error", function(error_msg)
			logger.error("Stream error: " .. tostring(error_msg))
			render_message("error", "Stream error: " .. tostring(error_msg))

			-- Reset thinking state on error
			state.is_thinking = false
			state.assistant_response_started = false
			logger.info("Reset is_thinking to false due to error")
		end),
	})
end

-- Creates and configures the user input window
local function create_input_window(parent_win_id)
	local width = api.nvim_win_get_width(parent_win_id)
	local height = 3 -- A small, visible height for the input box
	local row = api.nvim_win_get_height(parent_win_id) - height
	local col = 0

	state.input_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.input_buf, "filetype", "ollama_chat_input")

	local win_opts = {
		relative = "win",
		win = parent_win_id,
		anchor = "SW",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = config_module.get_config().ui.border_style,
	}
	state.input_win = api.nvim_open_win(state.input_buf, true, win_opts)
	api.nvim_win_set_option(state.input_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

	-- Keymaps for the input buffer
	api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"q",
		"<Cmd>lua require'ollama_chat.chat'.close()<CR>",
		{ noremap = true, silent = true }
	)
	api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<CR>",
		"<Cmd>lua require'ollama_chat.chat'.send_input()<CR>",
		{ noremap = true, silent = true }
	)

	-- Additional keymaps for better UX
	api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"<CR>",
		"<Cmd>lua require'ollama_chat.chat'.send_input()<CR>",
		{ noremap = true, silent = true }
	)

	-- Start in insert mode for immediate typing
	vim.schedule(function()
		if state.input_win and api.nvim_win_is_valid(state.input_win) then
			api.nvim_set_current_win(state.input_win)
			vim.cmd("startinsert")
		end
	end)
end

-- Creates and configures the main chat display window
local function create_chat_window()
	local config = config_module.get_config()
	local width = config.ui.chat_win_width
	local height = math.floor(api.nvim_get_option("lines") * 0.8)
	local row = math.floor((api.nvim_get_option("lines") - height) / 2)
	local col = math.floor((api.nvim_get_option("columns") - width) / 2)

	state.chat_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.chat_buf, "filetype", "markdown")
	api.nvim_buf_set_option(state.chat_buf, "modifiable", false)

	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = config.ui.border_style,
	}
	state.chat_win = api.nvim_open_win(state.chat_buf, true, win_opts)
	api.nvim_win_set_option(state.chat_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
end

-- Public function to open the chat interface
function M.open()
	logger.info("Opening chat interface")
	if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
		logger.info("Chat window already open, focusing input")
		api.nvim_set_current_win(state.input_win)
		vim.cmd("startinsert")
		return
	end

	create_chat_window()
	create_input_window(state.chat_win)

	render_message(
		"system",
		"Welcome to Zomboco--I mean Ollama Chat.  Anything is possible at Zombo--er...Ollama Chat.  Type your prompt and press Enter.  Yeah."
	)
end

-- Add context window management
local function trim_context(messages, max_tokens)
	local config = config_module.get_config()
	local context_limit = config.ollama.context_window or 4096

	-- Keep system messages and trim older messages if needed
	if #messages > 20 then -- Arbitrary limit; make configurable
		local trimmed = { messages[1] } -- Keep system message if exists
		for i = math.max(2, #messages - 18), #messages do
			table.insert(trimmed, messages[i])
		end
		return trimmed
	end
	return messages
end

-- Public function to close the chat interface.
function M.close()
	close_chat_windows()
end

-- Internal function exposed for keymap execution
function M.send_input()
	logger.info("send_input called, is_thinking: " .. tostring(state.is_thinking))

	if state.is_thinking then
		logger.warn("Currently processing a request, please wait...")
		vim.notify("Please wait for the current response to complete...", vim.log.levels.WARN)
		return
	end

	-- Check server availability first
	client.is_server_available(function(available, error_msg)
		if not available then
			logger.error("Server not available: " .. (error_msg or "Unknown error"))
			render_message("error", "Ollama server is not available: " .. (error_msg or "Unknown error"))
			return
		end
		-- Continue with sending input
		logger.info("Server available, sending input")
		vim.schedule(function()
			send_current_input()
		end)
	end)
end

-- Utility function to check current state (for debugging)
function M.debug_state()
	logger.info("=== DEBUG STATE ===")
	logger.info("is_thinking: " .. tostring(state.is_thinking))
	logger.info("assistant_response_started: " .. tostring(state.assistant_response_started))
	logger.info("session_messages count: " .. #state.session_messages)
	logger.info("chat_buf valid: " .. tostring(state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)))
	logger.info("input_buf valid: " .. tostring(state.input_buf and api.nvim_buf_is_valid(state.input_buf)))
	logger.info("==================")

	-- Also print to user
	print("Ollama Chat Debug:")
	print("- Thinking: " .. tostring(state.is_thinking))
	print("- Messages: " .. #state.session_messages)
	print("- Buffers valid: " .. tostring(state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)))
end

return M
