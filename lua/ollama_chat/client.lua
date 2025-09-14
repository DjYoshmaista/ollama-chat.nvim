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
				logger.ERROR("Ollama server not reachable.  Exit code: " .. tostring(response.exit))
				callback(false, "Server not reachable.  Exit code: " .. tostring(response.exit))
			else
				logger.INFO("Ollama server available and reachable!")
				callback(true, nil)
			end
		end,
	})
end

local function process_stream_data(data, on_chunk, on_finish, on_error)
	local buffer = ""
	return function(chunk)
		buffer = buffer .. chunk
		local lines = vim.split(buffer, "\n", { plain = true })

		-- Keep the last potentially incomplete line in buffer
		buffer = lines[#lines] or ""

		for i = 1, #lines - 1 do
			local line = lines[i]
			if line ~= "" then
				local ok, decoded = pcall(vim.json.decode, line)
				if ok then
					-- process decoded JSON
					if decoded.message and decoded.message.content then
						on_chunk(decoded.message.content)
					elseif decoded.done then
						on_finish(decoded)
					end
				else
					logger.ERROR("Failed to decode JSON: " .. line)
				end
			end
		end
	end
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
	local Job = require("plenary.job")

	-- Ensure required parameters are provided
	if not (params.model and params.messages and params.on_chunk and params.on_finish and params.on_error) then
		if params.on_error then
			logger.ERROR("stream_chat: Missing required parameters - model, messages, on_chunk, on_finish, on_error")
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
	logger.INFO("stream_chat: Body - " .. body_json)

	-- Create an instance of the stream processor using the existing helper function
	local process_chunk = process_stream_data(nil, params.on_chunk, params.on_finish, params.on_error)

	Job.new({
		command = "curl",
		args = {
			"-X",
			"POST",
			url,
			"-H",
			"Content-Type: application/json",
			"-d",
			body_json,
			"--no-buffer",
		},
		-- on_stdout is called for each piece of data from the stream
		on_stdout = function(err, data)
			if err then
				logger.ERROR("Error on stdout: " .. tostring(err))
				params.on_error("Error receiving data: " .. tostring(err))
				return
			end
			if data and data ~= "" then
				logger.INFO("RAW CHUNK RECEIVED: " .. tostring(data))
				process_chunk(data)
			end
		end,
		-- on_stderr is called if the curl command itself produces errors
		on_stderr = function(err, data)
			if err then
				logger.ERROR("Error on stderr: " .. tostring(err))
				params.on_error("Error during request: " .. tostring(err))
				return
			end
			if data and data ~= "" then
				logger.ERROR("curl stderr: " .. data)
				params.on_error("Request Error: " .. data)
			end
		end,
	}):start()
end

return M
