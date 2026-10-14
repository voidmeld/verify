--!strict

local process = require "@std/process"
local Lute = require "../src/lute"
local StudioEdit = require "./lib/studio-edit"
local probes = require "../tests/fixtures/datatype-probes"

local USAGE =
	"usage: lute run tools/export-studio-probes.luau <out.json> (--studio-id <id> | --studio-name <name>) [--mcp <StudioMCP>]"

local output: string? = nil
local target: StudioEdit.Target = {}
local index = 2
while index <= #process.args do
	local flag = process.args[index]
	if string.sub(flag, 1, 2) == "--" then
		local value = process.args[index + 1]
		if value == nil then
			error(USAGE, 0)
		end
		index += 1
		if flag == "--studio-id" then
			target.studioId = value
		elseif flag == "--studio-name" then
			target.studioName = value
		elseif flag == "--mcp" then
			target.mcp = value
		else
			error(USAGE, 0)
		end
	elseif output == nil then
		output = flag
	else
		error(USAGE, 0)
	end
	index += 1
end
if output == nil or (target.studioId == nil and target.studioName == nil) then
	error(USAGE, 0)
end

local recorded = StudioEdit.run(target, ".lute/tmp/verify-export-probes", function(execute)
	return Lute.fixture.probeStudio(execute, probes)
end)
Lute.fixture.save(output :: string, recorded)
print(
	("wrote %d probe results from Studio %s to %s"):format(#probes, tostring(recorded.engineVersion), output :: string)
)
