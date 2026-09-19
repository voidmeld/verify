--!strict

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function finiteNonnegative(value: any): boolean
	return finite(value) and value >= 0
end

local function nonnegativeInteger(value: any): boolean
	return finiteNonnegative(value) and value % 1 == 0
end

local function denseRows(value: any, count: number): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil or #value ~= count then
		return false
	end
	for key in value do
		if type(key) == "userdata" then
			continue
		end
		if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
			return false
		end
	end
	return true
end

local function deeplyFinite(value: any): boolean
	if type(value) == "number" then
		return finite(value)
	end
	if type(value) ~= "table" then
		return true
	end
	for key, child in value do
		if not deeplyFinite(key) or not deeplyFinite(child) then
			return false
		end
	end
	return true
end

local function safeId(value: any): boolean
	return type(value) == "string"
		and #(value :: string) >= 1
		and #(value :: string) <= 64
		and string.match(value :: string, "^[A-Za-z0-9][A-Za-z0-9._-]*$") ~= nil
end

local function nonempty(value: unknown): boolean
	return type(value) == "string" and #(value :: string) > 0
end

local function exactKeys(value: any, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return false
	end
	for key in value do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	for key in fields do
		if value[key] == nil then
			return false
		end
	end
	return true
end

local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end
	for key in value :: any do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	return true
end

local function copyStrings(value: unknown, label: string): { string }
	if type(value) ~= "table" then
		error(label .. " must be an array", 3)
	end
	local result: { string } = {}
	for index, item in value :: { unknown } do
		if type(index) ~= "number" or index ~= #result + 1 or type(item) ~= "string" then
			error(label .. " must be a dense string array", 3)
		end
		table.insert(result, item)
	end
	return result
end

local function requiredString(value: unknown, label: string): string
	if type(value) ~= "string" or value == "" then
		error(label .. " must be a non-empty string", 3)
	end
	return value
end

local function nonnegativeNumber(value: unknown, label: string): number
	if type(value) ~= "number" or value < 0 then
		error(label .. " must be a non-negative number", 3)
	end
	return value
end

return {
	copyStrings = copyStrings,
	requiredString = requiredString,
	nonnegativeNumber = nonnegativeNumber,
	finite = finite,
	finiteNonnegative = finiteNonnegative,
	nonnegativeInteger = nonnegativeInteger,
	denseRows = denseRows,
	deeplyFinite = deeplyFinite,
	safeId = safeId,
	nonempty = nonempty,
	exact = exactKeys,
	exactKeys = exactKeys,
	hasOnlyFields = hasOnlyFields,
}
