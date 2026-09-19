--!strict

local Walk = require "./lib/walk"
local process = require "@std/process"

local forbidden = {
	"@std/",
	"@lute/",
	"game",
	"script",
	"Instance",
	"task.",
	"process",
	"filesystem",
}

local failures: { string } = {}

for _, file in Walk.files("src/core", { ".luau" }) do
	for _, token in forbidden do
		if string.find(file.contents, token, 1, true) ~= nil then
			table.insert(failures, ("%s names forbidden core token %q"):format(file.path, token))
		end
	end
end
if #failures > 0 then
	for _, failure in failures do
		print(failure)
	end
	process.exit(1)
end
print "boundary: verify-core is host-neutral"
