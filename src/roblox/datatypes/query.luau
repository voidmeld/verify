--!strict

local Enum = require "./enum"
local Float = require "./float"
local Names = require "./names"

export type Filter = {
	FilterDescendantsInstances: { unknown },
	FilterType: Enum.EnumItem,
	IncludeInstances: { unknown }?,
	ExcludeInstances: { unknown }?,
	CollisionGroup: string,
	RespectCanCollide: boolean,
	BruteForceAllSlow: boolean,
	AddToFilter: (Filter, unknown) -> (),
}
export type RaycastParamsValue = Filter & { IgnoreWater: boolean, Margin: number, SizeGradient: number }
export type OverlapParamsValue = Filter & { MaxParts: number, Tolerance: number }
export type RaycastParamsConstructor = { new: () -> RaycastParamsValue }
export type OverlapParamsConstructor = { new: () -> OverlapParamsValue }

type State = { values: Names.Fields, lists: { [unknown]: { unknown } } }

local LISTS: { [unknown]: boolean } =
	{ FilterDescendantsInstances = true, IncludeInstances = true, ExcludeInstances = true }

local function append(target: { unknown }, value: unknown, visiting: { [unknown]: boolean })
	if Names.kind(value) == "Instance" then
		table.insert(target, value)
	elseif type(value) == "table" then
		assert(not visiting[value], "cyclic instance filter")
		visiting[value] = true
		for _, child in value :: { unknown } do
			append(target, child, visiting)
		end
		visiting[value] = nil
	else
		error("Invalid value type; table must only contain Instances and other tables", 3)
	end
end

local function constructor<T>(name: string, enums: Enum.Enums, make: (Names.Behavior, Names.Fields) -> T): () -> T
	local kind = Names.behavior(name)
	local storage = {}
	local states: { [unknown]: State } = {}
	Names.weak(states)
	local function state(value: unknown): State
		return states[value]
	end
	local function add(self: Filter, instances: unknown)
		append(state(self).lists.FilterDescendantsInstances, instances, {})
	end
	kind.fields.__index = function(fields: Names.Fields, key: unknown): unknown
		if key == "AddToFilter" then
			return add
		end
		local stored = state(fields)
		local value = stored.values[key]
		if LISTS[key] then
			local list = stored.lists[key]
			return if list == nil then nil else table.clone(list)
		end
		if value ~= nil then
			return value
		end
		return Names.missing(kind, key)
	end
	kind.meta.__newindex = function(self: unknown, key: unknown, value: unknown)
		local stored = state(self)
		local values = stored.values
		if LISTS[key] then
			if value == nil and key ~= "FilterDescendantsInstances" then
				values[key] = nil
				stored.lists[key] = nil
				return
			end
			assert(type(value) == "table", "instance filter must be an array")
			local list: { unknown } = {}
			values[key] = list
			stored.lists[key] = list
			append(list, value, {})
		elseif key == "FilterType" then
			assert(Enum.isItem(value) and Enum.enumType(value) == "RaycastFilterType", "RaycastFilterType expected")
			values[key] = value
		elseif key == "CollisionGroup" then
			assert(type(value) == "string", "CollisionGroup must be a string")
			values[key] = value
		elseif
			key == "RespectCanCollide"
			or key == "BruteForceAllSlow"
			or (key == "IgnoreWater" and name == "RaycastParams")
		then
			values[key] = not not value
		elseif name == "RaycastParams" and (key == "Margin" or key == "SizeGradient") then
			local number = Float.coerce(value, 3)
			assert(
				number == number and math.abs(number) < math.huge and number >= (if key == "Margin" then 0 else -1),
				"invalid cast expansion"
			)
			values[key] = number
		elseif name == "OverlapParams" and (key == "MaxParts" or key == "Tolerance") then
			local number = Float.coerce(value, 3)
			if key == "Tolerance" and not (number >= 0 and number <= 0.05) then
				error(("Tolerance outside bounds: Expected 0 - 0.050000, got %f"):format(number), 2)
			end
			values[key] = if key == "MaxParts" then Float.int32(number) else Float.f32(number)
		else
			Names.missing(kind, key)
		end
	end
	return function(): T
		local initialList: { unknown } = {}
		local values: Names.Fields = {
			FilterDescendantsInstances = initialList,
			FilterType = enums.RaycastFilterType.Exclude,
			CollisionGroup = "Default",
			RespectCanCollide = false,
			BruteForceAllSlow = false,
		}
		if name == "RaycastParams" then
			values.IgnoreWater = false
			values.Margin, values.SizeGradient = 0, 0
		else
			values.MaxParts, values.Tolerance = 0, 0
		end
		local stored: State = { values = values, lists = { FilterDescendantsInstances = initialList } }
		local fields: Names.Fields = { [storage] = stored }
		local made = make(kind, fields)
		states[made], states[fields] = stored, stored
		return made
	end
end

return {
	raycast = function(enums: Enum.Enums): RaycastParamsConstructor
		local make: (Names.Behavior, Names.Fields) -> RaycastParamsValue = Names.make
		local new = constructor("RaycastParams", enums, make)
		return { new = new }
	end,
	overlap = function(enums: Enum.Enums): OverlapParamsConstructor
		local make: (Names.Behavior, Names.Fields) -> OverlapParamsValue = Names.make
		local new = constructor("OverlapParams", enums, make)
		return { new = new }
	end,
}
