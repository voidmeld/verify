--!strict

local json = require "@std/json"

local Verify = require "../core"
local objectMarker: unknown
for key in json.object {} do
	objectMarker = key
end

local function normalize(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local result: { [unknown]: unknown } = {}
	for key, item in value do
		if type(key) == "string" or type(key) == "number" then
			result[key] = normalize(item)
		end
	end
	return result
end

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "expected a record")
	local result: { [string]: unknown } = {}
	for key, item in value do
		if type(key) == "string" then
			result[key] = item
		end
	end
	return result
end

local function array(value: unknown): { unknown }
	assert(type(value) == "table", "expected an array")
	local result: { unknown } = {}
	for _, item in value do
		table.insert(result, item)
	end
	return result
end

local function jsonValue(value: unknown, active: { [unknown]: boolean }): json.Value
	if value == nil or value == json.null then
		return json.null
	elseif type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
		return value
	end
	assert(type(value) == "table", "cannot encode " .. type(value) .. " as JSON")
	assert(not active[value], "cannot encode a cyclic table as JSON")
	active[value] = true
	local result: json.Value
	local object = false
	if #value == 0 then
		for _ in value do
			object = true
			break
		end
	end
	if not object and #value > 0 then
		local items: json.Array = {}
		for key, item in value do
			assert(type(key) == "number", "JSON array keys must be numbers")
			items[key] = jsonValue(item, active)
		end
		result = items
	else
		local fields: json.Object = {}
		for key, item in value do
			if key == objectMarker then
				continue
			end
			assert(type(key) == "string", "JSON object keys must be strings")
			fields[key] = jsonValue(item, active)
		end
		result = if object then json.object(fields) else fields
	end
	active[value] = nil
	return result
end

local function encode(value: unknown): string
	return json.serialize(jsonValue(value, {}))
end

local function pretty(value: unknown): string
	return json.serialize(jsonValue(value, {}), true)
end

local function parse(encoded: string): unknown
	return normalize(json.deserialize(encoded))
end

local function decode(encoded: string): Verify.Report
	return Verify.decode(parse(encoded))
end

return {
	encode = encode,
	pretty = pretty,
	record = record,
	array = array,
	parse = parse,
	decode = decode,
}
