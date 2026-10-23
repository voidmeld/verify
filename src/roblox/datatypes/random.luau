--!strict

local Generator = require "../../random"
local Names = require "./names"
local Vector = require "./vector"

export type RandomValue = {
	NextNumber: (RandomValue, number?, number?) -> number,
	NextInteger: (RandomValue, number, number) -> number,
	NextUnitVector: (RandomValue) -> Vector.Vector3Value,
	Shuffle: (RandomValue, { [unknown]: unknown }) -> (),
	Clone: (RandomValue) -> RandomValue,
}

local kind = Names.behavior "Random"
local stateKey = {}
local serial = 0

local function state(self: RandomValue): Generator.Generator
	assert(Names.is(self, kind), "Random expected")
	return Names.fields(self)[stateKey] :: Generator.Generator
end

local function create(generator: Generator.Generator): RandomValue
	return Names.make(kind, { [stateKey] = generator })
end

local function bounds(minimum: number, maximum: number): (number, number)
	assert(type(minimum) == "number" and minimum == minimum and math.abs(minimum) < math.huge, "minimum must be finite")
	assert(type(maximum) == "number" and maximum == maximum and math.abs(maximum) < math.huge, "maximum must be finite")
	return math.min(minimum, maximum), math.max(minimum, maximum)
end

local function integer(self: RandomValue, minimum: number, maximum: number): number
	local low, high = bounds(minimum, maximum)
	low, high = math.modf(low), math.modf(high)
	assert(
		math.abs(low) < 2 ^ 53 and math.abs(high) < 2 ^ 53 and high - low < 2 ^ 53,
		"integer range exceeds exact numeric precision"
	)
	return state(self).integer(low, high)
end

local methods: { [string]: unknown } = {
	NextNumber = function(self: RandomValue, minimum: number?, maximum: number?): number
		assert((minimum == nil) == (maximum == nil), "Random:NextNumber requires 0 or 2 arguments")
		local low, high = bounds(minimum or 0, maximum or 1)
		local value = state(self).next()
		return low * (1 - value) + high * value
	end,
	NextInteger = integer,
	NextUnitVector = function(self: RandomValue): Vector.Vector3Value
		local generator = state(self)
		local z, angle = generator.next() * 2 - 1, generator.next() * math.pi * 2
		local radius = math.sqrt(1 - z * z)
		return Vector.Vector3.new(radius * math.cos(angle), radius * math.sin(angle), z)
	end,
	Shuffle = function(self: RandomValue, values: { [unknown]: unknown })
		assert(type(values) == "table" and not table.isfrozen(values), "Shuffle requires a mutable table")
		local length = rawlen(values)
		for index = 1, length do
			assert(rawget(values, index) ~= nil, "Shuffle does not accept holes")
		end
		for index = length, 2, -1 do
			local target = integer(self, 1, index)
			local value = rawget(values, index)
			rawset(values, index, rawget(values, target))
			rawset(values, target, value)
		end
	end,
	Clone = function(self: RandomValue): RandomValue
		return create(state(self).clone())
	end,
}

kind.fields.__index = function(_fields: Names.Fields, key: unknown): unknown
	return methods[key :: string] or Names.missing(kind, key)
end

return {
	new = function(seed: number?): RandomValue
		if seed == nil then
			serial += 1
			seed = Generator.hash(("%.9f:%d"):format(os.clock(), serial))
		end
		assert(type(seed) == "number", "Random seed must be numeric")
		seed = if seed ~= seed or math.abs(seed) >= 2 ^ 53 then 0 else math.modf(seed)
		return create(Generator.generator(Generator.hash(("%.0f"):format(if seed == 0 then 0 else seed))))
	end,
}
