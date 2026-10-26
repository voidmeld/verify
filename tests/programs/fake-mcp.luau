--!strict

local fs = require "@std/fs"
local input = require "@lute/io"
local io = require "@std/io"
local process = require "@std/process"

local root = assert(process.args[2], "fake-mcp needs its directory")
if fs.exists(root .. "/broken") then
	process.exit(0)
end
while true do
	local line = input.read()
	local id = string.match(line, '"id":(%d+)')
	if id ~= nil then
		if string.find(line, "die_now", 1, true) ~= nil then
			process.exit(0)
		end
		local text = if string.find(line, "list_roblox_studios", 1, true) ~= nil
			then '[{\\"id\\":\\"studio-a\\",\\"name\\":\\"A\\"}]'
			else "ok"
		io.write(('{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"%s"}]}}\n'):format(id, text))
	end
end
