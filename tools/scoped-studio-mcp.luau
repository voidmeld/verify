--!strict

local Shape = require "../src/core/shape"
local fs = require "@std/fs"
local io = require "@lute/io"
local process = require "@std/process"
local json = require "@std/json"
local Eval = require "../src/agent-eval"
local Mcp = require "../src/lute/studio-mcp"
local Files = require "../src/lute/files"
local Wire = require "../src/lute/wire"

local path = process.args[2]
assert(path ~= nil and #process.args == 2, "usage: lute run tools/scoped-studio-mcp.luau <run scope file>")
local raw = Shape.record(Eval.lute.decode(fs.readFileToString(path)), "scope")
local studio = Shape.record(raw.studio, "scope studio")
local identity =
	{ id = Shape.requiredString(studio.id, "studio id"), name = Shape.requiredString(studio.name, "studio name") }
local executable = Shape.requiredString(raw.executable, "executable")
local directory = Shape.requiredString(raw.directory, "directory")
local seconds = raw.seconds
assert(type(seconds) == "number", "seconds must be a number")
local callSeconds = raw.callSeconds or 60
assert(
	type(callSeconds) == "number" and callSeconds > 0 and callSeconds < math.huge,
	"callSeconds must be finite and positive"
)
assert(seconds > 0 and seconds < math.huge, "seconds must be finite and positive")
local deadline = os.clock() + seconds
local transport: Mcp.Connection? = Mcp.connect(executable, Files.claimDirectory(directory), deadline)
local callFailure: string? = nil
local function dropTransport()
	local previous = transport
	transport = nil
	if previous then
		previous.close()
	end
end
local function encode(value: unknown): string
	return Wire.encode(value)
end
local scope = Eval.scopedMcp.create(identity, {
	call = function(name, arguments): unknown
		local now = os.clock()
		assert(now < deadline, "the run deadline expired before the scoped Studio call")
		if transport == nil then
			transport = Mcp.connect(executable, Files.claimDirectory(directory), deadline)
		end
		local limit = math.min(now + callSeconds, deadline)
		local called, value = pcall(assert(transport).callRaw, name, encode(arguments), limit, nil)
		if not called then
			callFailure =
				"the scoped Studio call failed without a response; it may have been applied; inspect state before repeating it"
			dropTransport()
			error(callFailure, 0)
		end
		local reply = value
		if reply.status ~= "answered" then
			callFailure = if reply.status == "unanswered"
				then "the scoped Studio call did not return; it may have been applied; inspect state before repeating it"
				else "the scoped Studio call was not sent"
			dropTransport()
			error(callFailure, 0)
		end
		assert(reply.detail == nil, "the scoped Studio backend returned an error")
		assert(type(reply.result) == "table", "the scoped Studio backend returned no result")
		return reply.result
	end,
}, encode)
local function respond(line: string)
	local request = Shape.record(Eval.lute.decode(line), "request")
	local method = Shape.requiredString(request.method, "request method")
	if request.id ~= nil then
		callFailure = nil
		local ok, result = pcall(function(): unknown
			assert(os.clock() < deadline, "the scoped Studio run deadline expired")
			return scope.dispatch(method, request.params)
		end)
		if ok and request.method == "ping" then
			result = json.object {}
		end
		local response = if ok
			then { jsonrpc = "2.0", id = request.id, result = result }
			else {
				jsonrpc = "2.0",
				id = request.id,
				error = { code = -32602, message = callFailure or tostring(result) },
			}
		io.write(encode(response) .. "\n")
	end
end
local served, problem = pcall(function()
	local pending = ""
	while os.clock() < deadline do
		local read, chunk = pcall(io.read)
		if not read or chunk == "" then
			break
		end
		pending ..= chunk
		while true do
			local ending = string.find(pending, "\n", 1, true)
			if ending == nil then
				break
			end
			local line = string.sub(pending, 1, ending - 1)
			pending = string.sub(pending, ending + 1)
			if line ~= "" then
				respond(line)
			end
		end
	end
end)
scope.close()
dropTransport()

assert(served, tostring(problem))
