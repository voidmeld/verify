--!strict

local process = require "@std/process"
local Lute = require "../src/lute"
local StudioEdit = require "./lib/studio-edit"

local USAGE = "usage: lute run tools/export-studio-reflection.luau <out.json> (--studio-id <id> | --studio-name <name>)"
	.. " [--classes A,B,...]... [--enums A,B,...]... [--services] [--mcp <StudioMCP>] [--framework <directory>]"

local output: string? = nil
local target: StudioEdit.Target = {}
local services = false
local classes: { string }? = nil
local enums: { string }? = nil
local framework = process.args[1]:match "^(.*)[/\\]tools[/\\]export%-studio%-reflection%.luau$" or "."

local function names(list: { string }?, value: string): { string }
	local out = list or {}
	for name in string.gmatch(value, "[^,%s]+") do
		table.insert(out, name)
	end
	return out
end

local index = 2
while index <= #process.args do
	local flag = process.args[index]
	if flag == "--services" then
		services = true
	elseif string.sub(flag, 1, 2) == "--" then
		local value = process.args[index + 1]
		if value == nil then
			error(USAGE, 0)
		end
		index += 1
		if flag == "--studio-id" then
			target.studioId = value
		elseif flag == "--studio-name" then
			target.studioName = value
		elseif flag == "--classes" then
			classes = names(classes, value)
		elseif flag == "--enums" then
			enums = names(enums, value)
		elseif flag == "--mcp" then
			target.mcp = value
		elseif flag == "--framework" then
			framework = value
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

local snapshot = StudioEdit.run(target, ".lute/tmp/verify-export-reflection", function(execute)
	return Lute.fixture.exportStudio(execute, {
		classes = classes,
		enums = enums,
		services = services,
		framework = framework,
	})
end)
Lute.fixture.save(output :: string, snapshot)
local classCount, enumCount = 0, 0
for _ in snapshot.classes do
	classCount += 1
end
local families = snapshot.enums
if families ~= nil then
	for _ in families do
		enumCount += 1
	end
end
print(
	("wrote %d classes and %d enums from Studio %s to %s"):format(
		classCount,
		enumCount,
		tostring(snapshot.engineVersion),
		output :: string
	)
)
