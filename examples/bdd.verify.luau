--!strict

local Bdd = require "../src/bdd"
local Verify = require "../src/core"

return function(harness: Verify.Harness)
	local bdd = Bdd.create(harness)

	bdd.describe("bdd authoring", function()
		local opened: { string } = {}

		bdd.beforeEach(function(own)
			table.insert(opened, "resource")
			own(function()
				table.remove(opened)
			end)
		end)

		bdd.it("expresses expectations through the shared matcher set", function()
			bdd.expect(2 + 2):toBe(4)
			bdd.expect(opened):toEqual { "resource" }
		end)

		bdd.itSkip("declared skips stay skips", "kept for the executor to select")
	end)
end
