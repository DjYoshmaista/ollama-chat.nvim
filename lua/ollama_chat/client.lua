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

-- Process stream data - simplified to work with Ollama's JSON-per-line format
local function process_stream_data(on_chunk, on_finish, on_error)
	local has_finished = false

	return function(chunk)
		if has_finished then
			return
		end

		logger.info("process_stream_data: Processing chunk: " .. tostring(chunk))

		-- Ollama sends complete JSON objects, usually one per chunk
		-- Try to decode the chunk directly first
		local trimmed_chunk = chunk:match("^%s*(.-)%s*$")
		if trimmed_chunk and trimmed_chunk ~= "" then
			logger.info("process_stream_data: Processing trimmed chunk: " .. trimmed_chunk)

			local success, decoded = pcall(vim.json.decode, trimmed_chunk)
			if success and decoded then
				logger.info("process_stream_data: Successfully decoded JSON from chunk")

				if decoded.done then
					logger.info("process_stream_data: Stream finished")
					has_finished = true
					on_finish(decoded)
					return
				elseif decoded.message and decoded.message.content then
					local content = decoded.message.content
					logger.info("process_stream_data: Calling on_chunk with: '" .. content .. "'")
					on_chunk(content)
				elseif decoded.error then
					logger.error("process_stream_data: Server error: " .. tostring(decoded.error))
					has_finished = true
					on_error("Server error: " .. tostring(decoded.error))
					return
				end
			else
				logger.warn("process_stream_data: Failed to decode JSON chunk: " .. trimmed_chunk)
				-- For debugging - let's see what we couldn't decode
				logger.debug("process_stream_data: Decode error was: " .. tostring(decoded))
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
		local error_msg = "stream_chat: Missing required parameters (model, messages, on_chunk, on_finish, on_error)"
		logger.error(error_msg)
		if params.on_error then
			params.on_error(error_msg)
		end
		return
	end

	local body_tbl = {
		model = params.model,
		messages = params.messages,
		stream = true,
	}

	local success, body_json = pcall(vim.json.encode, body_tbl)
	if not success then
		local error_msg = "Failed to encode request body: " .. tostring(body_json)
		logger.error(error_msg)
		params.on_error(error_msg)
		return
	end

	logger.info("stream_chat: Body - " .. body_json)

	-- Create the processor function
	local process_chunk = process_stream_data(params.on_chunk, params.on_finish, params.on_error)
	local job_finished = false

	local job = Job:new({
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
			"--no-buffer",
		},
		on_stdout = function(err, data)
			if job_finished then
				return
			end

			if err then
				logger.error("Error on stdout: " .. tostring(err))
				job_finished = true
				params.on_error("Error receiving data: " .. tostring(err))
				return
			end

			if data and data ~= "" then
				logger.info("RAW CHUNK RECEIVED: " .. tostring(data))
				process_chunk(data)
			end
		end,
		on_stderr = function(err, data)
			if job_finished then
				return
			end

			if data and data ~= "" then
				logger.error("curl stderr: " .. data)
				job_finished = true
				params.on_error("Request Error: " .. data)
			elseif err then
				logger.error("Error on stderr: " .. tostring(err))
				job_finished = true
				params.on_error("Error during request: " .. tostring(err))
			end
		end,
		on_exit = function(j, return_val)
			if job_finished then
				return
			end

			logger.info("curl exited with code: " .. tostring(return_val))
			if return_val ~= 0 then
				job_finished = true
				params.on_error("curl exited with non-zero code: " .. tostring(return_val))
			end
		end,
	})

	-- Start the job
	job:start()

	-- Return job handle for potential cancellation
	return job
end

-- Get available models (placeholder - implement if needed)
function M.get_available_models(callback)
	local url = get_base_url() .. "/api/tags"

	curl.get(url, {
		callback = function(response)
			if response.exit ~= 0 or response.status ~= 200 then
				logger.error("Failed to get models: " .. tostring(response.exit))
				callback({})
				return
			end

			local success, decoded = pcall(vim.json.decode, response.body)
			if success and decoded and decoded.models then
				local model_names = {}
				for _, model in ipairs(decoded.models) do
					table.insert(model_names, model.name)
				end
				callback(model_names)
			else
				logger.error("Failed to decode models response")
				callback({})
			end
		end,
	})
end

return M
