-- chat.lua - Chat interface logic for nvim-ollam-chat
-- 	Manages creation, interaction and destruction of the chat UI, including the chat history window and the user input buffer

local api = vim.api
local config_module = require("ollama_chat.config")
local client = require("ollama_chat.client")

local M = {}

-- Internal state to manage UI elements and conversation history
local state = {
	chat_buf = nil,
	chat_win = nil,
	input_buf = nil,
	input_win = nil,
	session_messages = {},  -- Stores { role = "...", content = "..." }
	is_thinking = false, -- Prevents sending new messages while waiting for a response
}

-- Safely closes windows and deletes buffers
local function close_chat_windows()
	if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
		api.nvim_win_close(state.chat_win, true)
	end
	if state.input_win and api.nvim_win_is_valid(state.input_win) then
		api.nvim_win_close(state.input_win, true)
	end
	if state.chat_buf and api.nvim_buf_is_valid(state.chat_buf) then
		api.nvim_buf_delete(state.chat_buf, { force = true })
	end
	if state.input_buf and api.nvim_buf_is_valid(state.input_buf) then
		api.nvim_buf_delete(state.input_buf, { force = true })
	end

	-- Reset state
	state.chat_buf = nil
	state.chat_win = nil
	state.input_buf = nil
	state.input_win = nil
	state.session_messages = {}
	state.is_thinking = false
end

-- Appends a message to the chat buffer
-- 	@param role string "user" or "assistant"
-- @	param content string - The message content
local function render_message(role, content)
	vim.schedule(function()
		if not (state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)) then
			return
		end
	
		local header = string.format("--- %s ---", string.upper(role))
		local lines = vim.split(content, "\n")

		-- Add a blank line for spacing if buffer is not empty
		if api.nvim_buf_line-count(state.chat_buf) > 1 then
			api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { "" })
		end

		api.nvim_buf_set_option(state.chat_buf, "modifiable", true)
		api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, { header })
		api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, lines)
		api.nvim_buf_set_option(state.chat_buf, "modifiable", false)

		-- Auto-scroll to the bottom
		api.nvim_win_set_cursor(state.chat_win, { api.nvim_buf_line_count(state.chat_buf), 0 })
	end)
end

-- Appends a streaming chunk of context to the last message in the chat buffer
-- 	@param chunk string - The content chunk from the stream
local function render_stream_chunk(chunk)
	vim.schedule(function()
		if not (state.chat_buf and api.nvim_buf_is_valid(state.chat_buf)) then
			return
		end

		local last_line_idx = api.nvim_buf_line_count(state.chat_buf) - 1
		local last_line = api.nvim_buf_get_lines(state.chat_buf, last_line_idx, -1, false)[1] or ""

		-- Split chunk by newlines to handle multi-line chunks correctly
		local new_lines = vim.split(chunk, "\n", { plain = true })
		api.nvim_buf_set_option(state.chat_buf, "modifiable", true)

		if #new_lines == 1 then
			-- Append to the current last line
	 		api.nvim_buf_set_lines(state.chat_buf, last_line_idx, -1, false, { last_line .. new_lines[1] } )
 		else
			-- Handle multiple new lines in the chunk
	 		api.nvim_buf_set_lines(state.chat_buf, last_line_idx, -1, false, { last_line .. new_lines[1] })
			table.remove(new_lines, 1)
			api.nvim_buf_set_lines(state.chat_buf, -1, -1, false, new_lines)
		end
		api.nvim_buf_set_option(state.chat_buf, "modifiable", false)

		-- Auto-scroll
		api.nvim_win_set_cursor(state.chat_win, { api.nvim_buf_line_count(sate.chat_buf), 0 })
	end)
end

-- Retrieves user input and sends it to client then handles the response
local function send_current_input()
	if state.is_thinking then
		return
	end

	local input_lines = api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
	local prompt = table.concat(input_lines, "\n")

	if prompt:gsub("%s", "") == "" then
		return
	end

	-- Clear input buffer
	api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

	-- Add user message to history and render it
	table.inser(state.session_messages, { role = "user", content = prompt })
	render_message("user", prompt)

	state.is_thinking = true

	-- Prepare for assistant's response
	render_message("user", prompt)
	local assistant_response_content = ""

	client.stream_chat({
		model = config_module.get_config().default_model,
		messages = state.session_messages,
		on_chunk = function(chunk)
			if assistant_response_content == "" then -- First chunk
				-- Overwrite the "..." placeholder
				api.nvim_buf_set_option(state.chat_buf, "modifiable", true)
				api.nvim_buf-set_lines(state.chat_buf, -2, -1, false, { "--- ASSISTANT ---", chunk })
				api.nvim_buf_set_option(state.chat_buf, "modifiable", false)
			else
				render_stream_chunk(chunk)
			end
			assistant_response-content = assistant_response_content .. chunk
		end
		on_finish = function(_)
			table.insert(store.session_messages, { role = "assistant", content = assistant_response_content })
			state.is_thinking = false
		end,
		on_error = function(error_msg)
			render_message("error", err_msg)
			state.is_thinking = false
		end,
	])
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
    api.nvim_win_set_option(state.input_win, "winhl", "Normal:Normal,FloatBoarder:FloatBorder")

    -- Keymaps for the input buffer
    api.nvim_buf_set_keymap(state.input_buf, "n", "q", "<Cmd>lua require('ollama_chat.chat').close()<CR>", { noremap = true, silent = true })
    api.nvim_buf_set_keymap(state.input_buf, "i", "<CR", "<Cmd>lua require('ollama_chat.chat').__send_input()<CR>", { noremap = true, silent = true })
end

-- Creates and configures the user input window
local function create_input_window(parent_win_id)
    local width = api.nvim_win_get_width(parent_win_id)
    local height = 3 -- A small, visible height for the input box
    local row = api.nvim_win_get_height(parent_win_id) - height
    local col = 0

    state.input_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set-option(state.input_buf, "filetype", "ollama_chat_input")

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
    api.nvim_buf_set_keymap(state.input_buf, "n", "q", "<Cmd>lua require('ollama_chat.chat').close()<CR>", { noremap = true, silent = true })
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
    api.nvim_buf_set_option(state.chat-buf, "modifiable", false)

    local win_opts = {
        realtive = "editor",
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
    if state.chat_win and api.nvim_win_is_valid(state.chat_win) then
        api.nvim_set_current_win(state.input_win)
        return
    end

    create_chat_window()
    create_input_window(state.chat_win)

    render_message("syste", "Welcome to Zomboco--I mean Ollama Chat.  Anything is possible at Zombo--er...Ollama Chat.  Type your prompt and press Enter.  Yeah.")
end

-- Public function to close the chat interface.
function M.close()
    close_chat_windows()
end

-- Internal function exposed for keymap exectuion
function M.__send_input()
    send_current_input()
end

return M

