--!strict

local json = require "@std/json"

local Verify = require "../core"

type PlanBatch = Verify.PlanBatch
type PlanUnit = Verify.PlanUnit

local WIRE_VERSION = 1

local function encode(batch: PlanBatch): string
	local units: { { [string]: any } } = {}
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
	return json.serialize {
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

local function decode(encoded: string): PlanBatch
	local parsed, value: any = pcall(json.deserialize, encoded)
	if not parsed then
		error("unparseable batch: " .. tostring(value), 2)
	end
	if type(value) ~= "table" then
		error("a batch must decode to a table", 2)
	end
	local raw = value :: { [string]: any }
	if raw.wireVersion ~= WIRE_VERSION then
		error(("unsupported batch wire version %s; expected %d"):format(tostring(raw.wireVersion), WIRE_VERSION), 2)
	end
	if type(raw.index) ~= "number" then
		error("batch wire index must be a number", 2)
	end
	local units: { PlanUnit } = {}
	for _, item in raw.units :: { any } do
		table.insert(units, {
			id = requiredString(item.id, "unit id"),
			locator = requiredString(item.locator, "unit locator"),
			group = item.group,
			tags = strings(item.tags),
			requires = strings(item.requires),
			deadlineSeconds = item.deadlineSeconds,
			weight = if type(item.weight) == "number" then item.weight else 1,
		})
	end
	return {
		id = requiredString(raw.id, "id"),
		index = raw.index,
		units = units,
		deadlineSeconds = raw.deadlineSeconds,
	}
end

return {
	WIRE_VERSION = WIRE_VERSION,
	encode = encode,
	decode = decode,
}
