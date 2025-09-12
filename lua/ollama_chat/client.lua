-- client.lua - lua client for ollama: Handles HTTP comm with local or remote Ollama server including streaming chat responses

local curl = require("plenary.curl")
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

-- Sends a chat request to the Ollama API and streams repsonse
-- @param params table Parameters for the chat request:
-- 	- model (string): Model name to use
-- 	- messages (table): List of message objects ( { role = "user", context = "Hi" } )
-- 	- on_chunk (function): Callback for each received data chunk - Receives the chunk context (string)
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

	local body = {
		model = params.model,
		messages = params.messages,
		stream = true,
	}

	logger.debug("stream_chat: Body - " .. vim.inspect(body))

	-- Buffer to hold incomplete data between chunks
	local remaining_buffer = ""

	curl.request({
		method = "POST",
		url = url,
		json = body,
		headers = {
			["Content-Type"] = "application/json",
		},
		-- Callback is invoked for each piece of data received from thes erver.
		on_body = function(chunk)
			logger.debug("RAW CHUNK RECEIVED: " .. tostring(chunk))

			local data = remaining_buffer .. chunk
			remaining_buffer = ""

			-- Process each line-seeparated JSON object in the chunk
			for line in data:gmatch("[^\n]*\n?") do
				-- Remove trailing newline if present
				line = line:gsub("\n$", "")
				-- Skip empty lines
				if #line == 0 then
					goto continue
				end

				logger.debug("PROCESSING LINE: " .. line)

				-- Check if line looks like a complete JSON object (starts with { ends with })
				if line:match("^%s*{") and line:match("}%s*$") then -- check if the line appears to be a complete JSON object
					local ok, decoded = pcall(vim.json.decode, line)
					if ok then
						logger.debug("DECODED SUCCESSFULLY: " .. vim.inspect(decoded))
						-- Streaming chunk: message content
						if decoded.done == false and decoded.message and decoded.message.content then
							params.on_chunk(decoded.message.content)
						-- Final message: stream ended
						elseif decoded.done == true then
							params.on_finish(decoded)
						end
					else
						-- TODO: Log malformed JSON and other errors
						logger.error("OllamaChat: Malformed JSON line: " .. line)
					end
				else
					-- Store incomplete line in buffer for next chunk
					remaining_buffer = line
				end

				::continue::
			end
		end,

		-- Callback is invoked once after entire request is complete
		callback = function(response)
			if response.exit ~= 0 or (response.status < 200 or response.status >= 300) then
				local error_msg = string.format(
					"Failed to connect to Ollama server.  Exit code: %d, Status: %d",
					response.exit,
					response.status,
					response.body or "No body"
				)
				logger.error(error_msg)
				params.on_error(error_msg)
				return
			end

			if #remaining_buffer > 0 then
				logger.error("Stream ended with incomplete data: " .. remaining_buffer)
				params.on_error("Stream ended with incomplete data:" .. remaining_buffer)
				remaining_buffer = ""
			end
		end,
	})
end

return M
