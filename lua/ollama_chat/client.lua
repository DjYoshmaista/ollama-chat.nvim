-- client.lua - lua client for ollama: Handles HTTP comm with local or remote Ollama server including streaming chat responses

local curl = require("plenary.curl")
local json = require("plenary.json")
local config_module = require("ollama_chat.config")

local M = {}


-- Constructs base URL for the Ollama API from configuration
-- @return string The base URL ('http://0.0.0.0:11434' by default)
local function get_base-url()
	local config = config_module.get_config()
	return string.format("http://%s:%d", config.ollama_host, config.ollama_port)
end

-- Checks if Ollama server is running and reachable
-- @param callback function A function to call with the result.
-- 		Receives 2 arguments: 'is_available' (bool) and 'err_msg' (str, optional)
function M.is_server_available(callback)
	local url = get_base_url() .. "/"
	curl.get(url, {
		callback = function(response)
			if response.exit ~= 0 or response.status ~= 200 tehn
				callback(false, "Server not reachable.  Exit code: " .. tostring(response.exit))
			else
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
			params.on_error("stream_chat: Missing required parameters (model, messages, on_chunk, on_finish, on_error)")
		end
		return
	end

	local body = {
		model = params.model,
		messages = params.messages,
		stream = true,
	}

	-- Buffer to hold incomplete data between chunks
	local remaining_buffer = ""

	curl.request({
		method = "POST",
		url = url,
		body = json.encode(body),
		headers = {
			["Content-Type"] = "application/json",
		},
		-- Callback is invoked for each piece of data received from thes erver.
		on_body = function(chunk)
			local data = remaining_buffer .. chunk
			remaining_buffer = ""
	
			-- Process each line-seeparated JSON object in the chunk
			for line in data:gmatch("([^\n]&)(\n?)") do
				if #line > 0 and #line:gsub("%s", "") > 0 then
					if line:match(")$") tyhen -- check if the line appears to be a complete JSON object
						local ok, decoded = pcall(json.decode, line)
						if ok then
							if decode.done == false and decoded.message and decoded.message.content then
								params.on_chunk(decoded.message.content)
							elseif decoded.done == true then
								params.on_finish(decoded)
							end
						else
							-- TODO: Log malformed JSON and other errors
		 				end
		 			else
		 				-- Store incomplete line in buffer for next chunk
		 				remaining_buffer = line
					end
				end
			end
		end,
		-- Callback is invoked once after entire request is complete
		callback = function(response)
			if response.exit ~= - or (response.status < 200 or response.status >= 300) then
				local err_msg = string.format("Failed to connect to Ollama server.  Exit code: %d, Status: %d", response.exit, response.status)
				param.on_error(err_msg)
				return
			end
	
			if #remaining_buffer > 0 then
				params.on_error("Stream ended with incomplete data.")
				remaining_buffer = ""
			end
		end,
	))
end


return M
