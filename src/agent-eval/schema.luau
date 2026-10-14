--!strict

export type Record = { [string]: unknown }

local function absent(value: unknown): boolean
	return value == nil or type(value) == "userdata"
end

local function fail(label: string, message: string): never
	error(("%s %s"):format(label, message), 0)
end

local function record(value: unknown, label: string): Record
	if type(value) ~= "table" then
		fail(label, "must be an object")
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) ~= "string" then
			fail(label, "must be an object with string keys")
		end
	end
	return value :: Record
end

local function only(value: Record, label: string, fields: { string })
	local allowed: { [string]: boolean } = {}
	for _, field in fields do
		allowed[field] = true
	end
	for key in value do
		if not allowed[key] then
			fail(label, ("has an unknown field %q"):format(key))
		end
	end
end

local function text(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" then
		fail(label, "must be a non-empty string")
	end
	return value :: string
end

local function optionalText(value: unknown, label: string): string?
	if absent(value) then
		return nil
	end
	return text(value, label)
end

local function identifier(value: unknown, label: string): string
	local candidate = text(value, label)
	if #candidate > 64 or string.match(candidate, "^[A-Za-z0-9][A-Za-z0-9._-]*$") == nil then
		fail(label, "must be an identifier of letters, digits, '.', '_' or '-' (at most 64 characters)")
	end
	return candidate
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function number(value: unknown, label: string, minimum: number?, integer: boolean?): number
	if not finite(value) then
		fail(label, "must be a finite number")
	end
	local result = value :: number
	if minimum ~= nil and result < minimum then
		fail(label, ("must be at least %s"):format(tostring(minimum)))
	end
	if integer == true and result % 1 ~= 0 then
		fail(label, "must be an integer")
	end
	return result
end

local function optionalNumber(value: unknown, label: string, minimum: number?, integer: boolean?): number?
	if absent(value) then
		return nil
	end
	return number(value, label, minimum, integer)
end

local function flag(value: unknown, label: string, default: boolean): boolean
	if absent(value) then
		return default
	end
	if type(value) ~= "boolean" then
		fail(label, "must be a boolean")
	end
	return value :: boolean
end

local function list(value: unknown, label: string): { unknown }
	if absent(value) then
		return {}
	end
	if type(value) ~= "table" then
		fail(label, "must be an array")
	end
	local result: { unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			fail(label, "must be an array")
		end
		result[key :: number] = item
	end
	for index = 1, #result do
		if result[index] == nil then
			fail(label, "must be a dense array")
		end
	end
	local count = 0
	for _ in result do
		count += 1
	end
	if count ~= #result then
		fail(label, "must be a dense array")
	end
	return result
end

local function texts(value: unknown, label: string): { string }
	local result: { string } = {}
	for index, item in list(value, label) do
		table.insert(result, text(item, ("%s[%d]"):format(label, index)))
	end
	return result
end

local function optionalTexts(value: unknown, label: string): { string }?
	if absent(value) then
		return nil
	end
	return texts(value, label)
end

local function dictionary(value: unknown, label: string): { [string]: string }
	if absent(value) then
		return {}
	end
	local result: { [string]: string } = {}
	for key, item in record(value, label) do
		if type(item) ~= "string" then
			fail(("%s.%s"):format(label, key), "must be a string")
		end
		result[key] = item :: string
	end
	return result
end

local function unique(values: { string }, label: string)
	local seen: { [string]: boolean } = {}
	for _, value in values do
		if seen[value] then
			fail(label, ("repeats %q"):format(value))
		end
		seen[value] = true
	end
end

local function sortedKeys<T>(value: { [string]: T }): { string }
	local keys: { string } = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function canonical(value: unknown): string
	local kind = type(value)
	if kind == "string" then
		return string.format("%q", value :: string)
	elseif kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind ~= "table" then
		return "null"
	end
	local items = value :: { [unknown]: unknown }
	local count = 0
	for _ in items do
		count += 1
	end
	if count > 0 and #(items :: { unknown }) == count then
		local pieces: { string } = {}
		for _, item in items :: { unknown } do
			table.insert(pieces, canonical(item))
		end
		return "[" .. table.concat(pieces, ",") .. "]"
	end
	local pieces: { string } = {}
	for key, item in items do
		table.insert(pieces, canonical(tostring(key)) .. ":" .. canonical(item))
	end
	table.sort(pieces)
	return "{" .. table.concat(pieces, ",") .. "}"
end

return {
	absent = absent,
	fail = fail,
	record = record,
	only = only,
	text = text,
	optionalText = optionalText,
	identifier = identifier,
	finite = finite,
	number = number,
	optionalNumber = optionalNumber,
	flag = flag,
	list = list,
	texts = texts,
	optionalTexts = optionalTexts,
	dictionary = dictionary,
	unique = unique,
	sortedKeys = sortedKeys,
	canonical = canonical,
}
