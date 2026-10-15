--!strict

local fs = require "@std/fs"
local io = require "@std/io"
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
while os.clock() < deadline do
	local read, line = pcall(io.input)
	if not read or line == "" then
		break
	end
	local request = Eval.lute.decode(line) :: { id: unknown?, method: string, params: unknown? }
	if request.id ~= nil then
		local ok, result = pcall(scope.dispatch, request.method, request.params)
		local response = if ok
			then { jsonrpc = "2.0", id = request.id, result = result }
			else { jsonrpc = "2.0", id = request.id, error = { code = -32602, message = tostring(result) } }
		io.write(encode(response) .. "\n")
	end
end
scope.close()
transport.close()
