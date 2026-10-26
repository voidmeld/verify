--!strict

local Lute = require "../src/lute"
local Test = require "./harness"

Lute.selfRegisteringWorker {
	load = function(locator: string, harness)
		Test.useHarness(harness, function()
			local resolved, thrown: unknown = pcall(require, "../" .. string.sub(locator, 1, #locator - 5))
			if not resolved then
				error(thrown, 0)
			end
		end)
	end,
}
