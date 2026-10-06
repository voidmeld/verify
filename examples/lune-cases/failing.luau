--!strict

local Verify = require "../../src/core"

return function(harness: Verify.Harness)
	harness:case("intentional failure", function(context)
		context:expect(1 + 1):toBe(3)
	end)
end
