--!strict

local test = require "@std/test"

local Shape = require "../src/core/shape"

test.suite("shape predicates", function(suite)
	suite:case("finite accepts real numbers and rejects nan and infinities", function(assert)
		assert.eq(Shape.finite(1.5), true)
		assert.eq(Shape.finite(0), true)
		assert.eq(Shape.finite(math.huge), false)
		assert.eq(Shape.finite(-math.huge), false)
		assert.eq(Shape.finite(math.nan), false)
		assert.eq(Shape.finite "1", false)
	end)

	suite:case("finiteNonnegative rejects negatives and non-finite values", function(assert)
		assert.eq(Shape.finiteNonnegative(2), true)
		assert.eq(Shape.finiteNonnegative(0), true)
		assert.eq(Shape.finiteNonnegative(-1), false)
		assert.eq(Shape.finiteNonnegative(math.huge), false)
	end)

	suite:case("nonnegativeInteger requires a whole nonnegative number", function(assert)
		assert.eq(Shape.nonnegativeInteger(2), true)
		assert.eq(Shape.nonnegativeInteger(1.5), false)
		assert.eq(Shape.nonnegativeInteger(-1), false)
	end)

	suite:case("denseRows checks a metatable-free array of the exact length", function(assert)
		assert.eq(Shape.denseRows({ 1, 2, 3 }, 3), true)
		assert.eq(Shape.denseRows({ 1, 2 }, 3), false)
		assert.eq(Shape.denseRows({ 1, 2, 3, extra = true }, 3), false)
		assert.eq(Shape.denseRows(setmetatable({ 1 }, {}), 1), false)
		assert.eq(Shape.denseRows("rows", 1), false)
	end)

	suite:case("deeplyFinite walks nested tables for non-finite numbers", function(assert)
		assert.eq(Shape.deeplyFinite { a = { b = { 1, 2 } } }, true)
		assert.eq(Shape.deeplyFinite { a = { b = { math.huge } } }, false)
		assert.eq(Shape.deeplyFinite "text", true)
	end)

	suite:case("safeId bounds length and charset", function(assert)
		assert.eq(Shape.safeId "run-1.a", true)
		assert.eq(Shape.safeId "-run", false)
		assert.eq(Shape.safeId "run/1", false)
		assert.eq(Shape.safeId "", false)
		assert.eq(Shape.safeId(string.rep("a", 65)), false)
		assert.eq(Shape.safeId(7), false)
	end)

	suite:case("nonempty requires a non-blank string", function(assert)
		assert.eq(Shape.nonempty "a", true)
		assert.eq(Shape.nonempty "", false)
		assert.eq(Shape.nonempty(7), false)
	end)

	suite:case("exactKeys requires every named field present and no others", function(assert)
		local fields = { a = true, b = true }
		assert.eq(Shape.exactKeys({ a = 1, b = 2 }, fields), true)
		assert.eq(Shape.exactKeys({ a = 1 }, fields), false)
		assert.eq(Shape.exactKeys({ a = 1, b = 2, c = 3 }, fields), false)
		assert.eq(Shape.exactKeys(setmetatable({ a = 1, b = 2 }, {}), fields), false)
		assert.eq(Shape.exactKeys("nope", fields), false)
	end)

	suite:case("exact is the same algorithm as exactKeys", function(assert)
		local fields = { a = true }
		assert.eq(Shape.exact({ a = 1 }, fields), true)
		assert.eq(Shape.exact({}, fields), false)
	end)

	suite:case("hasOnlyFields allows an absent field but never an extra one", function(assert)
		local fields = { a = true, b = true }
		assert.eq(Shape.hasOnlyFields({ a = 1 }, fields), true)
		assert.eq(Shape.hasOnlyFields({}, fields), true)
		assert.eq(Shape.hasOnlyFields({ a = 1, c = 2 }, fields), false)
		assert.eq(Shape.hasOnlyFields("nope", fields), false)
	end)
end)
