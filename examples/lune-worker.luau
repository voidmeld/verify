--!strict

local Lune = require "../src/lune"

Lune.worker {
	load = function(locator: string): unknown
		local resolved, value: unknown = pcall(require, "./" .. locator)
		if not resolved then
			error(value, 0)
		end
		return value
	end,
}
