--!strict

local Verify = require "../../src/core"

return function(harness: Verify.Harness)
	harness:suite("arithmetic", function()
		harness:case("adds", function(context)
			context:expect(1 + 1):toBe(2)
		end)
		harness:case("concatenates", function(context)
			context:expect("a" .. "b"):toBe "ab"
		end)
	end)
end
