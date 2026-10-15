--!strict

local fs = require "@std/fs"
local Core = require "../src/core"
local Files = require "../src/lute/files"

return function(context: Core.Context, name: string): string
	local directory = Files.claimDirectory(Files.temporary(name))
	context:defer(function()
		fs.removeDirectory(directory, { recursive = true })
	end)
	return directory
end
