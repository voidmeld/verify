--!strict

local Lune = require "../../../src/lune"
local Verify = require "../../../src/core"

local operations: Lune.WorkerOperations = {
	load = function(locator: string): unknown
		if locator == "raises" then
			return require "./raiser"
		end
		return function(harness: Verify.Harness)
			harness:case("fine", function(context)
				context:expect(1):toBe(1)
			end)
		end
	end,
}

Lune.worker(operations)
