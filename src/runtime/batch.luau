--!strict

local Verify = require "../core"
local Binding = require "./binding"

type PlanBatch = Verify.PlanBatch
type PlanUnit = Verify.PlanUnit

export type Batch = {
	WIRE_VERSION: number,
	encode: (batch: PlanBatch) -> string,
	decode: (encoded: string) -> PlanBatch,
}

local WIRE_VERSION = 1

local function encodeWith(json: Binding.Json, batch: PlanBatch): string
	local units: { PlanUnit } = {}
	for _, unit in batch.units do
		table.insert(units, {
			id = unit.id,
			locator = unit.locator,
			group = unit.group,
			tags = unit.tags,
			requires = unit.requires,
			deadlineSeconds = unit.deadlineSeconds,
			weight = unit.weight,
		})
	end
	return json.encode {
		wireVersion = WIRE_VERSION,
		id = batch.id,
		index = batch.index,
		deadlineSeconds = batch.deadlineSeconds,
		units = units,
	}
end

local function requiredString(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" then
		error(("batch wire %s must be a non-empty string"):format(label), 3)
	end
	return value
end

local function optionalString(value: unknown, label: string): string?
	if value == nil then
		return nil
	end
	if type(value) ~= "string" then
		error(("batch wire %s must be a string"):format(label), 3)
	end
	return value
end

local function optionalNumber(value: unknown, label: string): number?
	if value == nil then
		return nil
	end
	if type(value) ~= "number" then
		error(("batch wire %s must be a number"):format(label), 3)
	end
	return value
end

local function strings(value: unknown): { string }
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		error("batch wire string list must be an array", 3)
	end
	local result: { string } = {}
	for _, item in value :: { unknown } do
		if type(item) == "string" then
			table.insert(result, item)
		end
	end
	return result
end

local function decodeWith(json: Binding.Json, encoded: string): PlanBatch
	local parsed, value: unknown = pcall(json.decode, encoded)
	if not parsed then
		error("unparseable batch: " .. tostring(value), 2)
	end
	if type(value) ~= "table" then
		error("a batch must decode to a table", 2)
	end
	local raw = value :: { [string]: unknown }
	if raw.wireVersion ~= WIRE_VERSION then
		error(("unsupported batch wire version %s; expected %d"):format(tostring(raw.wireVersion), WIRE_VERSION), 2)
	end
	if type(raw.index) ~= "number" then
		error("batch wire index must be a number", 2)
	end
	assert(type(raw.units) == "table", "batch wire units must be an array")
	local units: { PlanUnit } = {}
	for _, rawUnit in raw.units :: { unknown } do
		assert(type(rawUnit) == "table", "batch unit must be a table")
		local item = rawUnit :: { [string]: unknown }
		table.insert(units, {
			id = requiredString(item.id, "unit id"),
			locator = requiredString(item.locator, "unit locator"),
			group = optionalString(item.group, "unit group"),
			tags = strings(item.tags),
			requires = strings(item.requires),
			deadlineSeconds = optionalNumber(item.deadlineSeconds, "unit deadlineSeconds"),
			weight = if type(item.weight) == "number" then item.weight else 1,
		})
	end
	return {
		id = requiredString(raw.id, "id"),
		index = raw.index,
		units = units,
		deadlineSeconds = optionalNumber(raw.deadlineSeconds, "deadlineSeconds"),
	}
end

local function create(json: Binding.Json): Batch
	return {
		WIRE_VERSION = WIRE_VERSION,
		encode = function(batch: PlanBatch): string
			return encodeWith(json, batch)
		end,
		decode = function(encoded: string): PlanBatch
			return decodeWith(json, encoded)
		end,
	}
end

return {
	WIRE_VERSION = WIRE_VERSION,
	create = create,
}
