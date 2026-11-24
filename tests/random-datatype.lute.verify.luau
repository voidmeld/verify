--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asNumber(value: unknown): number
	assert(type(value) == "number")
	return value
end

local Types = require "../src/roblox/datatypes"
local Random = Types.Random

local function rejectMetamethods(values: { [unknown]: unknown })
	setmetatable(values, {
		__len = function()
			error "length metamethod invoked"
		end,
		__index = function()
			error "index metamethod invoked"
		end,
		__newindex = function()
			error "write metamethod invoked"
		end,
	})
end

it("Random normalizes seeds and clones independent mixed-method streams", function()
	for _, seed in { 0, 0.9, -0.9, math.huge } do
		expect(Random.new(seed):NextNumber()):toBe(Random.new(0):NextNumber())
	end
	local first = Random.new(-42)
	first:NextNumber()
	local copy = first:Clone()
	for _ = 1, 30 do
		expect(first:NextNumber(10, 5)):toBe(copy:NextNumber(5, 10))
		expect(first:NextInteger(8.9, 2.2)):toBe(copy:NextInteger(2.2, 8.9))
		local direction = first:NextUnitVector()
		expect(direction):toBe(copy:NextUnitVector())
		expect(math.abs(direction.Magnitude - 1) < 0.000001):toBe(true)
	end
	expect(Types.typeof(first)):toBe "Random"
	expect((pcall(function()
		first:NextNumber(5)
	end))):toBe(false)
end)
it("Random shuffles only dense array entries without invoking metamethods", function()
	local values: { [unknown]: unknown } = { 1, 2, 3, 4, tag = "retained" }
	rejectMetamethods(values)
	Random.new(7):Shuffle(values)
	local ordered: { number } = {}
	for index = 1, 4 do
		table.insert(ordered, asNumber(rawget(values, index)))
	end
	table.sort(ordered)
	expect(ordered):toEqual { 1, 2, 3, 4 }
	expect(rawget(values, "tag")):toBe "retained"
	local broken: { [unknown]: unknown } = { 1, 2, 3, 4 }
	broken[2] = nil
	local random = Random.new(7)
	local copy = random:Clone()
	expect((pcall(function()
		random:Shuffle(broken)
	end))):toBe(false)
	expect(random:NextNumber()):toBe(copy:NextNumber())
end)

return nil
