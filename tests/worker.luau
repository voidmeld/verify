--!strict

local Worker = require "../src/lute/worker"
local Test = require "./harness"

Worker.mainSelfRegistering {
	load = function(locator: string, harness)
		Test.useHarness(harness, function()
			local resolved, thrown: unknown = pcall(require, "../" .. string.sub(locator, 1, #locator - 5))
			if not resolved then
				error(thrown, 0)
			end
		end)
	end,
}
