--!strict

local fs = require "@std/fs"
local io = require "@lute/io"
local process = require "@std/process"
local time = require "@std/time"

local target = process.args[2]
if target == nil or target == "" then
	print "usage: lute run stamp.luau <output file>"
	process.exit(2)
end

local handle = fs.open(target, "w")
local started = time.now()
local pending = ""

local function emit(at: number, line: string)
	fs.write(handle, ("%.6f\t%s\n"):format(at, (string.gsub(line, "\r$", ""))))
end

while true do
	local ok, chunk = pcall(io.read)
	if not ok or type(chunk) ~= "string" then
		break
	end
	local at = time.since(started)
	pending ..= chunk
	while true do
		local ending = string.find(pending, "\n", 1, true)
		if ending == nil then
			break
		end
		emit(at, string.sub(pending, 1, ending - 1))
		pending = string.sub(pending, ending + 1)
	end
end
if pending ~= "" then
	emit(time.since(started), pending)
end
fs.close(handle)
