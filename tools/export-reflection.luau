--!strict

local load = require :: (string) -> unknown
local fs = load "@lune/fs" :: { writeFile: (string, string) -> () }
local process = load "@lune/process" :: { args: { string }, exit: (number?) -> () }

local Lune = require "../src/lune"

local usage = "usage: lune run tools/export-reflection.luau <out.json> [--classes=A,B,...]"
local output: string? = nil
local classes: { string }? = nil
for _, argument in process.args do
	local list = string.match(argument, "^%-%-classes=(.+)$")
	if list ~= nil then
		classes = {}
		for name in string.gmatch(list, "[^,]+") do
			table.insert(classes :: { string }, name)
		end
	elseif string.sub(argument, 1, 2) == "--" or output ~= nil then
		error(usage, 0)
	else
		output = argument
	end
end
if output == nil then
	error(usage, 0)
end

local snapshot = Lune.exportReflection { classes = classes }
fs.writeFile(output :: string, Lune.serializeSnapshot(snapshot) .. "\n")
print(("wrote reflection snapshot to %s"):format(output :: string))
process.exit(0)
