--!strict

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function finiteNonnegative(value: unknown): boolean
	return type(value) == "number" and finite(value) and value >= 0
end

local function nonnegativeInteger(value: unknown): boolean
	return type(value) == "number" and finiteNonnegative(value) and value % 1 == 0
end

local function denseRows(value: unknown, count: number): boolean
	if
		type(value) ~= "table"
		or ((getmetatable :: unknown) :: (unknown) -> unknown)(value) ~= nil
		or #(value :: { unknown }) ~= count
	then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) == "userdata" then
			continue
		end
		if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
			return false
		end
	end
	return true
end

local function exactKeys(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" or ((getmetatable :: unknown) :: (unknown) -> unknown)(value) ~= nil then
		return false
	end
	for key in value :: { [unknown]: unknown } do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	for key in fields do
		if (value :: { [string]: unknown })[key] == nil then
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
	exact = exactKeys,
}
