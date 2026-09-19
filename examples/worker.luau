--!strict

local Lute = require "../src/lute"

Lute.worker {
	load = function(locator: string): unknown
		local resolved, value: any = pcall(require, "../" .. string.sub(locator, 1, #locator - 5))
		if not resolved then
			error(value, 0)
		end
		return value
	end,
}
