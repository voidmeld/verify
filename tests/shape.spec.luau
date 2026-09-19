--!strict

local Verify = require "../src/core"

local Shape = require "../src/core/shape"

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
			check:expect((Shape.nonnegativeInteger(2))):toEqual(true)
			check:expect((Shape.nonnegativeInteger(1.5))):toEqual(false)
			check:expect((Shape.nonnegativeInteger(-1))):toEqual(false)
		end)

		suite:case("denseRows checks a metatable-free array of the exact length", function(check)
			check:expect((Shape.denseRows({ 1, 2, 3 }, 3))):toEqual(true)
			check:expect((Shape.denseRows({ 1, 2 }, 3))):toEqual(false)
			check:expect((Shape.denseRows({ 1, 2, 3, extra = true }, 3))):toEqual(false)
			check:expect((Shape.denseRows(setmetatable({ 1 }, {}), 1))):toEqual(false)
			check:expect((Shape.denseRows("rows", 1))):toEqual(false)
		end)

		suite:case("deeplyFinite walks nested tables for non-finite numbers", function(check)
			check:expect(Shape.deeplyFinite { a = { b = { 1, 2 } } }):toEqual(true)
			check:expect(Shape.deeplyFinite { a = { b = { math.huge } } }):toEqual(false)
			check:expect(Shape.deeplyFinite "text"):toEqual(true)
		end)

		suite:case("safeId bounds length and charset", function(check)
			check:expect(Shape.safeId "run-1.a"):toEqual(true)
			check:expect(Shape.safeId "-run"):toEqual(false)
			check:expect(Shape.safeId "run/1"):toEqual(false)
			check:expect(Shape.safeId ""):toEqual(false)
			check:expect((Shape.safeId(string.rep("a", 65)))):toEqual(false)
			check:expect((Shape.safeId(7))):toEqual(false)
		end)

		suite:case("nonempty requires a non-blank string", function(check)
			check:expect(Shape.nonempty "a"):toEqual(true)
			check:expect(Shape.nonempty ""):toEqual(false)
			check:expect((Shape.nonempty(7))):toEqual(false)
		end)

		suite:case("exactKeys requires every named field present and no others", function(check)
			local fields = { a = true, b = true }
			check:expect((Shape.exactKeys({ a = 1, b = 2 }, fields))):toEqual(true)
			check:expect((Shape.exactKeys({ a = 1 }, fields))):toEqual(false)
			check:expect((Shape.exactKeys({ a = 1, b = 2, c = 3 }, fields))):toEqual(false)
			check:expect((Shape.exactKeys(setmetatable({ a = 1, b = 2 }, {}), fields))):toEqual(false)
			check:expect((Shape.exactKeys("nope", fields))):toEqual(false)
		end)

		suite:case("exact is the same algorithm as exactKeys", function(check)
			local fields = { a = true }
			check:expect((Shape.exact({ a = 1 }, fields))):toEqual(true)
			check:expect((Shape.exact({}, fields))):toEqual(false)
		end)

		suite:case("hasOnlyFields allows an absent field but never an extra one", function(check)
			local fields = { a = true, b = true }
			check:expect((Shape.hasOnlyFields({ a = 1 }, fields))):toEqual(true)
			check:expect((Shape.hasOnlyFields({}, fields))):toEqual(true)
			check:expect((Shape.hasOnlyFields({ a = 1, c = 2 }, fields))):toEqual(false)
			check:expect((Shape.hasOnlyFields("nope", fields))):toEqual(false)
		end)
	end)
end
