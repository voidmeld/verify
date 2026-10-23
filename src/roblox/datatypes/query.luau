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
export type RaycastParamsValue = Filter & { IgnoreWater: boolean }
export type OverlapParamsValue = Filter & { MaxParts: number, Tolerance: number }
export type RaycastParamsConstructor = { new: () -> RaycastParamsValue }
export type OverlapParamsConstructor = { new: () -> OverlapParamsValue }

local LISTS = { FilterDescendantsInstances = true, IncludeInstances = true, ExcludeInstances = true }

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

local function constructor(name: string, enums: Enum.Enums): () -> Filter
	local kind = Names.behavior(name)
	local storage = {}
	local function state(value: unknown): Names.Fields
		return Names.fields(value)[storage] :: Names.Fields
	end
	local function add(self: Filter, instances: unknown)
		append(state(self).FilterDescendantsInstances :: { unknown }, instances, {})
	end
	kind.fields.__index = function(fields: Names.Fields, key: unknown): unknown
		if key == "AddToFilter" then
			return add
		end
		local values = fields[storage] :: Names.Fields
		local value = values[key]
		if LISTS[key :: string] then
			return if value == nil then nil else table.clone(value :: { unknown })
		end
		if value ~= nil then
			return value
		end
		return Names.missing(kind, key)
	end
	kind.meta.__newindex = function(self: unknown, key: unknown, value: unknown)
		local values = state(self)
		if LISTS[key :: string] then
			if value == nil and key ~= "FilterDescendantsInstances" then
				values[key] = nil
				return
			end
			assert(type(value) == "table", "instance filter must be an array")
			local list: { unknown } = {}
			values[key] = list
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
	return function(): Filter
		local values: Names.Fields = {
			FilterDescendantsInstances = {},
			FilterType = enums.RaycastFilterType.Exclude,
			CollisionGroup = "Default",
			RespectCanCollide = false,
			BruteForceAllSlow = false,
		}
		if name == "RaycastParams" then
			values.IgnoreWater = false
		else
			values.MaxParts, values.Tolerance = 0, 0
		end
		return Names.make(kind, { [storage] = values })
	end
end

return {
	raycast = function(enums: Enum.Enums): RaycastParamsConstructor
		return { new = (constructor("RaycastParams", enums) :: unknown) :: () -> RaycastParamsValue }
	end,
	overlap = function(enums: Enum.Enums): OverlapParamsConstructor
		return { new = (constructor("OverlapParams", enums) :: unknown) :: () -> OverlapParamsValue }
	end,
}
