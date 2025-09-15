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

-- Calculate window positions based on configuration
--  @return table - Window positioning data
local function calculate_window_pos()
	local config = config_module.get_config()
	local ui = config.ui

	local editor_width = api.nvim_get_option("columns")
	local editor_height = api.nvim_get_option("lines")

	-- Chat window dimensions
	local chat_width = ui.chat_win_width
	local chat_height = ui.chat_win_height
	local input_width = ui.input_win_width or chat_width
	local input_height = ui.input_win_height
	local gap = ui.window_gap or 1

	-- Total height needed for both windows plus gap
	local total_height = chat_height + input_height + gap

	local pos = {}

	-- Calculate base position for the chat window
	if type(ui.chat_win_pos) == "table" then
		-- User specified exact coordinates
		pos.chat_row = ui.chat_win_pos.row
		pos.chat_col = ui.chat_win_pos.col
	elseif ui.chat_win_pos == "top" then
		pos.chat_row = 1
		pos.chat_col = math.floor((editor_width - chat_width) / 2)
	elseif ui.chat_win_pos == "bottom" then
		pos.chat_row = editor_height - total_height - 2 -- Leaves room for command
		pos.chat_col = math.floor((editor_width - chat_width) / 2)
	else -- "center" or default
		pos.chat_row = math.floor((editor_height - total_height) / 2)
		pos.chat_col = math.floor((editor_width - chat_width) / 2)
	end

	-- Calculate input window position based on layout
	if ui.layout == "horizontal" then
		-- Side by side layout
		pos.input_row = pos.chat_row
		pos.input_col = pos.chat_col + chat_width + gap
		-- Adjust input height to match chat height in horizontal layout
		input_height = chat_height
	else -- "vertical" layout (default)
		-- Input below chat
		pos.input_row = pos.chat_row + chat_height + gap
		pos.input_col = math.floor((editor_width - input_width) / 2)
	end

	return {
		chat = {
			width = chat_width,
			height = chat_height,
			row = pos.chat_row,
			col = pos.chat_col,
		},
		input = {
			width = input_width,
			height = input_height,
			row = pos.input_row,
			col = pos.input_col,
		},
	}
end

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

		local config = config_module.get_config()
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
		local config = config_module.get_config()
		if config.ui.auto_scroll and state.chat_win and api.nvim_win_is_valid(state.chat_win) then
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
local function create_input_window(pos)
	local config = config_module.get_config()

	state.input_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.input_buf, "filetype", "ollama_chat_input")

	local win_opts = {
		relative = "editor",
		width = pos.input.width,
		height = pos.input.height,
		row = pos.input.row,
		col = pos.input.col,
		style = "minimal",
		border = config.ui.border_style,
	}

	state.input_win = api.nvim_open_win(state.input_buf, false, win_opts)
	api.nvim_win_set_option(state.input_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

	-- Keymaps for the input buffer
	local keymaps = {
		{ "n", "q", "<Cmd>lua require'ollama_chat.chat'.close()<CR>" },
		{ "i", "<CR>", "<Cmd>lua require'ollama_chat.chat'.send_input()<CR>" },
		{ "n", "<CR>", "<Cmd>lua require'ollama_chat.chat'.send_input()<CR>" },
		{ "i", "<C-c>", "<Cmd>lua require'ollama_chat.chat'.close()<CR>" },
		{ "n", "<Esc>", "<Cmd>lua require'ollama_chat.chat'.close()<CR>" },
	}

	for _, keymap in ipairs(keymaps) do
		api.nvim_buf_set_keymap(state.input_buf, keymap[1], keymap[2], keymap[3], { noremap = true, silent = true })
	end

	-- Add placeholder text
	api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "Type your message here..." })

	-- Clear placeholder on insert
	api.nvim_create_autocmd({ "InsertEnter" }, {
		buffer = state.input_buf,
		callback = function()
			local lines = api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
			if #lines == 1 and lines[1] == "Type your message here..." then
				api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			end
		end,
		once = true,
	})
end

-- Creates and configures the main chat display window
local function create_chat_window(pos)
	local config = config_module.get_config()

	state.chat_buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_option(state.chat_buf, "filetype", "markdown")
	api.nvim_buf_set_option(state.chat_buf, "modifiable", false)

	local win_opts = {
		relative = "editor",
		width = pos.chat.width,
		height = pos.chat.height,
		row = pos.chat.row,
		col = pos.chat.col,
		style = "minimal",
		border = config.ui.border_style,
	}
	state.chat_win = api.nvim_open_win(state.chat_buf, false, win_opts)
	api.nvim_win_set_option(state.chat_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

	-- Make chat window read-only with useful keymaps
	local chat_keymaps = {
		{ "n", "q", "<Cmd>lua require'ollama_chat.chat'.close()<CR>" },
		{ "n", "<Esc>", "<Cmd>lua require'ollama_chat.chat'.close()<CR>" },
		{ "n", "i", "<Cmd>lua require'ollama_chat.chat'.focus_input()<CR>" },
		{ "n", "i", "<Cmd>lua require'ollama_chat.chat'.focus_input()<CR>" },
	}

	for _, keymap in ipairs(chat_keymaps) do
		api.nvim_buf_set_keymap(state.chat_buf, keymap[1], keymap[2], keymap[3], { noremap = true, silent = true })
	end
end

-- Public function to focus the input window
function M.focus_input()
	if state.input_win and api.nvim_win_is_valid(state.input_win) then
		api.nvim_set_current_win(state.input_win)
		local config = config_module.get_config()
		if config.ui.start_in_insert_mode then
			vim.cmd("startinsert")
		end
	end
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

	-- Calculate window positions based on configuration
	local positions = calculate_window_pos()

	-- Create windows
	create_chat_window(positions)
	create_input_window(positions)

	-- Show welcome message
	render_message(
		"system",
		"Welcome to Zomboco--I mean Ollama Chat.  Anything is possible at Zombo--er...Ollama Chat.  Type your prompt and press Enter.  Yeah."
	)

	-- Focus input window and start in insert mode if configured
	M.focus_input()
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

-- Function to resize windows dynamically
function M.resize_windows()
	if not (state.chat_win and state.input_win) then
		return
	end

	local positions = calculate_window_pos()

	if api.nvim_win_is_valid(state.chat_win) then
		api.nvim_win_set_config(state.chat_win, {
			relative = "editor",
			width = positions.chat.width,
			height = positions.chat.height,
			row = positions.chat.row,
			col = positions.chat.col,
		})
	end

	if api.nvim_win_is_valid(state.input_win) then
		api.nvim_win_set_config(state.input_win, {
			relative = "editor",
			width = positions.input.width,
			height = positions.input.height,
			row = positions.input.row,
			col = positions.input.col,
		})
	end
end

-- Set up auto-resize on window resize
vim.api.nvim_create_autocmd({ "VimResized" }, {
	callback = function()
		if state.chat_win and state.input_win then
			M.resize_windows()
		end
	end,
})

return M
