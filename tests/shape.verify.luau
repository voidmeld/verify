--!strict

local Verify = require "../src/core"

local InternalShape = require "../src/core/shape"
local Shape = Verify.shape

return function(suite: Verify.Harness)
	suite:suite("shape predicates", function()
		suite:case("finite accepts real numbers and rejects nan and infinities", function(check)
			check:expect((Shape.finite(1.5))):toEqual(true)
			check:expect((Shape.finite(0))):toEqual(true)
			check:expect((Shape.finite(math.huge))):toEqual(false)
			check:expect((Shape.finite(-math.huge))):toEqual(false)
			check:expect((Shape.finite(math.nan))):toEqual(false)
			check:expect(Shape.finite "1"):toEqual(false)
		end)

		suite:case("finiteNonnegative rejects negatives and non-finite values", function(check)
			check:expect((Shape.finiteNonnegative(2))):toEqual(true)
			check:expect((Shape.finiteNonnegative(0))):toEqual(true)
			check:expect((Shape.finiteNonnegative(-1))):toEqual(false)
			check:expect((Shape.finiteNonnegative(math.huge))):toEqual(false)
		end)

		suite:case("nonnegativeInteger requires a whole nonnegative number", function(check)
			check:expect((Shape.nonnegativeInteger(0))):toEqual(true)
			check:expect((Shape.nonnegativeInteger(2))):toEqual(true)
			check:expect((Shape.nonnegativeInteger(1.5))):toEqual(false)
			check:expect((Shape.nonnegativeInteger(-1))):toEqual(false)
		end)

		suite:case("denseRows checks a metatable-free array of the exact length", function(check)
			check:expect((Shape.denseRows({}, 0))):toEqual(true)
			check:expect((Shape.denseRows({ 1, 2, 3 }, 3))):toEqual(true)
			check:expect((Shape.denseRows({ 1, 2 }, 3))):toEqual(false)
			check:expect((Shape.denseRows({ 1, 2, 3, extra = true }, 3))):toEqual(false)
			check:expect((Shape.denseRows(setmetatable({ 1 }, {}), 1))):toEqual(false)
			check:expect((Shape.denseRows("rows", 1))):toEqual(false)
		end)

		suite:case("exact requires every named field present and no others", function(check)
			local fields = { a = true, b = true }
			check:expect((InternalShape.exact({ a = 1, b = 2 }, fields))):toEqual(true)
			check:expect((InternalShape.exact({ a = 1 }, fields))):toEqual(false)
			check:expect((InternalShape.exact({ a = 1, b = 2, c = 3 }, fields))):toEqual(false)
			check:expect((InternalShape.exact(setmetatable({ a = 1, b = 2 }, {}), fields))):toEqual(false)
			check:expect((InternalShape.exact("nope", fields))):toEqual(false)
		end)
	end)
end
