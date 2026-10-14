--!strict

local json = require "@std/json"

local Verify = require "../core"

local function normalize(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local result: { [unknown]: unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		if type(key) == "string" or type(key) == "number" then
			result[key] = normalize(item)
		end
	end
	return result
end

local function encode(value: unknown): string
	return json.serialize(value :: json.Value)
end

local function parse(encoded: string): unknown
	return normalize(json.deserialize(encoded))
end

local function decode(encoded: string): Verify.Report
	return Verify.decode(parse(encoded))
end

return {
	encode = encode,
	parse = parse,
	decode = decode,
}
