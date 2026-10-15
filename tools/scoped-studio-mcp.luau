--!strict

local fs = require "@std/fs"
local io = require "@lute/io"
local process = require "@std/process"
local json = require "@std/json"
local Eval = require "../src/agent-eval"
local Mcp = require "../src/lute/studio-mcp"

local path = process.args[2]
assert(path ~= nil and #process.args == 2, "usage: lute run tools/scoped-studio-mcp.luau <run scope file>")
local raw =
	Eval.lute.decode(fs.readFileToString(path)) :: { studio: { id: string, name: string }, executable: string, directory: string, seconds: number }
local deadline = os.clock() + raw.seconds
local transport = Mcp.connect(raw.executable, raw.directory, deadline)
local function encode(value: unknown): string
	return json.serialize(value :: json.Value)
end
local scope = Eval.scopedMcp.create(raw.studio, {
	call = function(name, arguments): unknown
		return transport.call(name, arguments)
	end,
}, encode)
local function respond(line: string)
	local request = Eval.lute.decode(line) :: { id: unknown?, method: string, params: unknown? }
	if request.id ~= nil then
		local ok, result = pcall(scope.dispatch, request.method, request.params)
		if ok and request.method == "ping" then
			result = json.object {}
		end
		local response = if ok
			then { jsonrpc = "2.0", id = request.id, result = result }
			else { jsonrpc = "2.0", id = request.id, error = { code = -32602, message = tostring(result) } }
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
transport.close()

assert(served, problem)
