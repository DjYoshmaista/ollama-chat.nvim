-- client.lua - lua client for ollama: Handles HTTP comm with local or remote Ollama server including streaming chat responses

local curl = require("plenary.curl")
local Job = require("plenary.job")
local config_module = require("ollama_chat.config")
local logger = require("ollama_chat.logger")

local M = {}

-- Constructs base URL for the Ollama API from configuration
-- @return string The base URL ('http://0.0.0.0:11434' by default)
local function get_base_url()
	local config = config_module.get_config()
	return string.format("http://%s:%d", config.ollama_host, config.ollama_port)
end

-- Checks if Ollama server is running and reachable
-- @param callback function A function to call with the result.
-- 		Receives 2 arguments: 'is_available' (bool) and 'error_msg' (str, optional)
function M.is_server_available(callback)
	local url = get_base_url() .. "/"
	curl.get(url, {
		callback = function(response)
			if response.exit ~= 0 or response.status ~= 200 then
				logger.error("Ollama server not reachable.  Exit code: " .. tostring(response.exit))
				callback(false, "Server not reachable.  Exit code: " .. tostring(response.exit))
			else
				logger.info("Ollama server available and reachable!")
				callback(true, nil)
			end
		end,
	})
end

-- FIXED: Proper stream processing that actually calls the callback
local function process_stream_data(data, on_chunk, on_finish, on_error)
	local buffer = ""
	return function(chunk)
		logger.info("process_stream_data: Processing chunk: " .. tostring(chunk))

		-- For Ollama, each chunk is typically a complete JSON line
		-- Let's try processing it directly first
		local trimmed_chunk = chunk:match("^%s*(.-)%s*$") -- trim whitespace

		if trimmed_chunk and trimmed_chunk ~= "" then
			logger.info("process_stream_data: Processing trimmed chunk as line: " .. trimmed_chunk)
			local ok, decoded = pcall(vim.json.decode, trimmed_chunk)
			if ok then
				logger.info("process_stream_data: Successfully decoded JSON from direct chunk")
				if decoded.message and decoded.message.content then
					local content = decoded.message.content
					logger.info("process_stream_data: Calling on_chunk with: '" .. content .. "'")
					on_chunk(content)
				elseif decoded.done then
					logger.info("process_stream_data: Stream done, calling on_finish")
					on_finish(decoded)
				end
				return -- Successfully processed, exit early
			else
				logger.warn(
					"process_stream_data: Failed to decode chunk directly, trying line-by-line: " .. trimmed_chunk
				)
			end
		end

		-- Fallback to line-by-line processing if direct processing fails
		buffer = buffer .. chunk
		local lines = vim.split(buffer, "\n", { plain = true })

		if #lines == 0 then
			return
		end

		-- Assume the last line might be incomplete
		buffer = table.remove(lines, #lines)

		for _, line in ipairs(lines) do
			local trimmed_line = line:match("^%s*(.-)%s*$") -- trim whitespace
			if trimmed_line and trimmed_line ~= "" then
				logger.info("process_stream_data: Processing line: " .. trimmed_line)
				local ok, decoded = pcall(vim.json.decode, trimmed_line)
				if ok then
					logger.info("process_stream_data: Successfully decoded JSON from line")
					if decoded.message and decoded.message.content then
						local content = decoded.message.content
						logger.info("process_stream_data: Calling on_chunk with: '" .. content .. "'")
						on_chunk(content)
					elseif decoded.done then
						logger.info("process_stream_data: Stream done, calling on_finish")
						on_finish(decoded)
					end
				else
					logger.error("process_stream_data: Failed to decode JSON line: " .. trimmed_line)
				end
			end
		end
	end
end

-- Sends a chat request to the Ollama API and streams response
-- @param params table Parameters for the chat request:
-- 	- model (string): Model name to use
-- 	- messages (table): List of message objects ( { role = "user", content = "Hi" } )
-- 	- on_chunk (function): Callback for each received data chunk - Receives the chunk content (string)
-- 	- on_finish (function): Callback for when the stream is complete. Receives the final response summary
-- 	- on_error (function): Callback for any errors - Receives an error message (string)
function M.stream_chat(params)
	local url = get_base_url() .. "/api/chat"

	-- Ensure required parameters are provided
	if not (params.model and params.messages and params.on_chunk and params.on_finish and params.on_error) then
		if params.on_error then
			logger.error("stream_chat: Missing required parameters - model, messages, on_chunk, on_finish, on_error")
			params.on_error("stream_chat: Missing required parameters (model, messages, on_chunk, on_finish, on_error)")
		end
		return
	end

	local body_tbl = {
		model = params.model,
		messages = params.messages,
		stream = true,
	}

	-- Manually encode the table into a JSON string
	local body_json = vim.json.encode(body_tbl)
	logger.info("stream_chat: Body - " .. body_json)

	-- FIXED: Create the processor function correctly
	local process_chunk = process_stream_data(body_json, params.on_chunk, params.on_finish, params.on_error)

	Job:new({
		command = "curl",
		args = {
			"-s",
			"-X",
			"POST",
			url,
			"-H",
			"Content-Type: application/json",
			"-d",
			body_json,
			"--no-buffer", -- This flag is CRUCIAL for streaming responses
		},
		on_stdout = function(err, data)
			if data and data ~= "" then
				logger.info("RAW CHUNK RECEIVED: " .. tostring(data))
				-- FIXED: Just call process_chunk with data - it's already configured with callbacks
				process_chunk(data)
			elseif err then
				logger.error("Error on stdout: " .. tostring(err))
				params.on_error("Error receiving data: " .. tostring(err))
				return
			end
		end,
		on_stderr = function(err, data)
			if data and data ~= "" then
				logger.error("curl stderr: " .. data)
				params.on_error("Request Error: " .. data)
			elseif err then
				logger.error("Error on stderr: " .. tostring(err))
				params.on_error("Error during request: " .. tostring(err))
				return
			end
		end,
	}):start()
end

return M
