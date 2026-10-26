--!strict

local function asNumber(value: unknown): number
	assert(type(value) == "number")
	return value
end

local Core = require "../src/core"
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

return function(suite: Core.Harness)
	suite:case("Random normalizes seeds and clones independent mixed-method streams", function(check)
		for _, seed in { 0, 0.9, -0.9, math.huge } do
			check:expect(Random.new(seed):NextNumber()):toBe(Random.new(0):NextNumber())
		end
		local first = Random.new(-42)
		first:NextNumber()
		local copy = first:Clone()
		for _ = 1, 30 do
			check:expect(first:NextNumber(10, 5)):toBe(copy:NextNumber(5, 10))
			check:expect(first:NextInteger(8.9, 2.2)):toBe(copy:NextInteger(2.2, 8.9))
			local direction = first:NextUnitVector()
			check:expect(direction):toBe(copy:NextUnitVector())
			check:expect(math.abs(direction.Magnitude - 1) < 0.000001):toBe(true)
		end
		check:expect(Types.typeof(first)):toBe "Random"
		check
			:expect((pcall(function()
				first:NextNumber(5)
			end)))
			:toBe(false)
	end)
	suite:case("Random shuffles only dense array entries without invoking metamethods", function(check)
		local values: { [unknown]: unknown } = { 1, 2, 3, 4, tag = "retained" }
		rejectMetamethods(values)
		Random.new(7):Shuffle(values)
		local ordered: { number } = {}
		for index = 1, 4 do
			table.insert(ordered, asNumber(rawget(values, index)))
		end
		table.sort(ordered)
		check:expect(ordered):toEqual { 1, 2, 3, 4 }
		check:expect(rawget(values, "tag")):toBe "retained"
		local broken: { [unknown]: unknown } = { 1, 2, 3, 4 }
		broken[2] = nil
		local random = Random.new(7)
		local copy = random:Clone()
		check
			:expect((pcall(function()
				random:Shuffle(broken)
			end)))
			:toBe(false)
		check:expect(random:NextNumber()):toBe(copy:NextNumber())
	end)
end
