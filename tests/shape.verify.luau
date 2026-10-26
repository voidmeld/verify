--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Verify = require "../src/core"

local InternalShape = require "../src/core/shape"
local Shape = Verify.shape

describe("shape predicates", function()
	it("finite accepts real numbers and rejects nan and infinities", function()
		expect((Shape.finite(1.5))):toEqual(true)
		expect((Shape.finite(0))):toEqual(true)
		expect((Shape.finite(math.huge))):toEqual(false)
		expect((Shape.finite(-math.huge))):toEqual(false)
		expect((Shape.finite(math.nan))):toEqual(false)
		expect(Shape.finite "1"):toEqual(false)
	end)

	it("finiteNonnegative rejects negatives and non-finite values", function()
		expect((Shape.finiteNonnegative(2))):toEqual(true)
		expect((Shape.finiteNonnegative(0))):toEqual(true)
		expect((Shape.finiteNonnegative(-1))):toEqual(false)
		expect((Shape.finiteNonnegative(math.huge))):toEqual(false)
	end)

	it("nonnegativeInteger requires a whole nonnegative number", function()
		expect((Shape.nonnegativeInteger(0))):toEqual(true)
		expect((Shape.nonnegativeInteger(2))):toEqual(true)
		expect((Shape.nonnegativeInteger(1.5))):toEqual(false)
		expect((Shape.nonnegativeInteger(-1))):toEqual(false)
	end)

	it("denseRows checks a metatable-free array of the exact length", function()
		expect((Shape.denseRows({}, 0))):toEqual(true)
		expect((Shape.denseRows({ 1, 2, 3 }, 3))):toEqual(true)
		expect((Shape.denseRows({ 1, 2 }, 3))):toEqual(false)
		expect((Shape.denseRows({ 1, 2, 3, extra = true }, 3))):toEqual(false)
		expect((Shape.denseRows(setmetatable({ 1 }, {}), 1))):toEqual(false)
		expect((Shape.denseRows("rows", 1))):toEqual(false)
	end)

	it("exact requires every named field present and no others", function()
		local fields = { a = true, b = true }
		expect((InternalShape.exact({ a = 1, b = 2 }, fields))):toEqual(true)
		expect((InternalShape.exact({ a = 1 }, fields))):toEqual(false)
		expect((InternalShape.exact({ a = 1, b = 2, c = 3 }, fields))):toEqual(false)
		expect((InternalShape.exact(setmetatable({ a = 1, b = 2 }, {}), fields))):toEqual(false)
		expect((InternalShape.exact("nope", fields))):toEqual(false)
	end)
end)

return nil
