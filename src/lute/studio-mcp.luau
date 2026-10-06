--!strict

local fs = require "@std/fs"
local process = require "@std/process"
local task = require "@std/task"
local json = require "@std/json"
local Bounded = require "./bounded"
local Files = require "./files"
local Operations = require "../core/operations"
local Wire = require "./wire"

export type Exchange = {
	status: "answered" | "unsent" | "unanswered",
	result: unknown?,
	detail: string?,
	lost: boolean?,
}

export type Connection = {
	call: (name: string, arguments: { [string]: unknown }) -> unknown,
	callRaw: (name: string, argumentsJson: string, deadline: number) -> Exchange,
	close: () -> (),
	alive: () -> boolean,
}

local EXITED = "studio_mcp_exited"
local WRITE_SECONDS = 3
local LIVENESS_SECONDS = 0.5

local META =
	'"_meta":{"io.modelcontextprotocol/protocolVersion":"2025-06-18","io.modelcontextprotocol/clientCapabilities":{}}'

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "Studio MCP returned a non-record")
	return value :: { [string]: unknown }
end

local function connect(executable: string, directory: string, deadline: number): Connection
	Files.ensureDirectory(directory)
	local fifo, output, errors = directory .. "/input", directory .. "/output", directory .. "/errors"
	local started = process.run {
		"sh",
		"-c",
		'mkfifo "$1" || exit 1; exec 3<>"$1"; "$2" <&3 >"$3" 2>"$4" & echo $!',
		"verify-mcp",
		fifo,
		executable,
		output,
		errors,
	}
	assert(started.ok, started.stderr)
	local pid = tonumber(string.match(started.stdout, "%d+"))
	assert(pid ~= nil, "Studio MCP did not start")
	local closed, sequence, consumed = false, 0, 0
	local requestFile = directory .. "/request"
	local function alive(): boolean
		return not closed and process.run({ "kill", "-0", tostring(pid) }).ok
	end
	local function send(line: string): (boolean, string?)
		fs.writeStringToFile(requestFile, line)
		local sent =
			Bounded.run({ "sh", "-c", 'cat "$1" 1<>"$2"', "verify-mcp-send", requestFile, fifo }, WRITE_SECONDS)
		if sent.unsupported then
			return false, "no process group could be created for the pipe write"
		end
		if sent.timedOut then
			return false, "the pipe write did not finish in " .. WRITE_SECONDS .. "s"
		end
		return sent.ok, if sent.ok then nil else sent.stderr
	end
	local answers: { [number]: { [string]: unknown } } = {}
	local function close()
		if closed then
			return
		end
		closed = true
		process.run { "kill", "-KILL", tostring(pid) }
	end
	local function exchange(method: string, paramsJson: string, limit: number): Exchange
		if closed or os.clock() >= limit then
			return { status = "unsent", detail = "Studio MCP deadline expired before " .. method }
		end
		sequence += 1
		local id = sequence
		local line = ('{"jsonrpc":"2.0","id":%d,"method":%s,"params":%s}\n'):format(
			id,
			json.serialize(method),
			paramsJson
		)
		if not alive() then
			return { status = "unsent", detail = EXITED, lost = true }
		end
		local wrote, reason = send(line)
		if not wrote then
			return { status = "unsent", detail = tostring(reason) }
		end
		local checkedAt = os.clock()
		while os.clock() < limit and not closed do
			local bytes = if fs.exists(output) then fs.readFileToString(output) else ""
			if #bytes > consumed then
				local chunk = bytes:sub(consumed + 1)
				for text in string.gmatch(chunk, "([^\n]+)\n") do
					local parsed, value: unknown = pcall(Wire.parse, text)
					if parsed and type(value) == "table" then
						local fields = value :: { [string]: unknown }
						if type(fields.id) == "number" then
							answers[fields.id] = fields
						end
					end
				end
				consumed += string.find(chunk, "\n[^\n]*$") or 0
			end
			local fields = answers[id]
			if fields ~= nil then
				answers[id] = nil
				if fields.error ~= nil then
					return { status = "answered", detail = json.serialize(fields.error :: json.Value) }
				end
				return { status = "answered", result = fields.result }
			end
			if os.clock() - checkedAt >= LIVENESS_SECONDS then
				checkedAt = os.clock()
				if not alive() then
					return { status = "unanswered", detail = EXITED, lost = true }
				end
			end
			task.wait(0.05)
		end
		return { status = "unanswered", detail = "Studio MCP deadline expired for " .. method }
	end
	local function handshake()
		local initialize = exchange(
			"initialize",
			'{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"},'
				.. META
				.. "}",
			deadline
		)
		assert(initialize.status == "answered" and initialize.detail == nil, initialize.detail or initialize.status)
		local notified, problem = send '{"jsonrpc":"2.0","method":"notifications/initialized"}\n'
		assert(notified, problem)
	end
	local ok, reason: unknown = pcall(handshake)
	if not ok then
		close()
		error(reason, 0)
	end
	local function callRaw(name: string, argumentsJson: string, limit: number): Exchange
		return exchange(
			"tools/call",
			('{"name":%s,"arguments":%s,%s}'):format(json.serialize(name), argumentsJson, META),
			limit
		)
	end
	return {
		close = close,
		alive = alive,
		callRaw = callRaw,
		call = function(name, arguments)
			local argumentsJson = if next(arguments) == nil
				then "{}"
				else json.serialize(Operations.snapshot(arguments) :: json.Value)
			local reply = callRaw(name, argumentsJson, deadline)
			assert(reply.status == "answered" and reply.detail == nil, reply.detail or reply.status)
			local result = record(reply.result)
			assert(
				result.isError ~= true,
				"Studio MCP tool failed: " .. json.serialize((result :: unknown) :: json.Value)
			)
			return result
		end,
	}
end

return { connect = connect, record = record, EXITED = EXITED }
