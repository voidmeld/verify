--!strict

export type Limits = {
	maxBytes: number?,
	maxCount: number?,
	maxTotalBytes: number?,
}

export type Resolved = {
	maxBytes: number,
	maxCount: number,
	maxTotalBytes: number,
}

local DEFAULT_MAX_BYTES = 1048576
local DEFAULT_MAX_COUNT = 16
local DEFAULT_MAX_TOTAL_BYTES = 4194304
local MAX_NAME_BYTES = 200

local function limit(value: number?, default: number, label: string): number
	if value == nil then
		return default
	end
	if type(value) ~= "number" or value ~= value or value < 1 or value % 1 ~= 0 or value == math.huge then
		error(("attachment %s must be a positive integer"):format(label), 3)
	end
	return value
end

local function resolve(limits: Limits?): Resolved
	local given: Limits = limits or {}
	return {
		maxBytes = limit(given.maxBytes, DEFAULT_MAX_BYTES, "maxBytes"),
		maxCount = limit(given.maxCount, DEFAULT_MAX_COUNT, "maxCount"),
		maxTotalBytes = limit(given.maxTotalBytes, DEFAULT_MAX_TOTAL_BYTES, "maxTotalBytes"),
	}
end

local function unsafeName(name: string): string?
	if name == "" then
		return "must not be empty"
	end
	if #name > MAX_NAME_BYTES then
		return ("must not exceed %d bytes"):format(MAX_NAME_BYTES)
	end
	if string.find(name, "[%c\\]") ~= nil then
		return "must not contain control characters or backslashes"
	end
	if string.sub(name, 1, 1) == "/" then
		return "must be a relative path"
	end
	for segment in string.gmatch(name .. "/", "([^/]*)/") do
		if segment == "" then
			return "must not contain an empty path segment"
		end
		if segment == "." or segment == ".." then
			return "must not contain a . or .. segment"
		end
	end
	return nil
end

local function check(name: string, mediaType: string, text: string, limits: Resolved): string?
	local unsafe = unsafeName(name)
	if unsafe ~= nil then
		return ("attachment name %q %s"):format(name, unsafe)
	end
	if mediaType == "" then
		return ("attachment %q needs a media type"):format(name)
	end
	if type(text) ~= "string" or text == "" then
		return ("attachment %q must hold non-empty text"):format(name)
	end
	if #text > limits.maxBytes then
		return ("attachment %q is %d bytes; the limit is %d"):format(name, #text, limits.maxBytes)
	end
	if utf8.len(text) == nil then
		return ("attachment %q is not valid UTF-8; only text is supported"):format(name)
	end
	return nil
end

return {
	DEFAULT_MAX_BYTES = DEFAULT_MAX_BYTES,
	DEFAULT_MAX_COUNT = DEFAULT_MAX_COUNT,
	DEFAULT_MAX_TOTAL_BYTES = DEFAULT_MAX_TOTAL_BYTES,
	resolve = resolve,
	check = check,
	unsafeName = unsafeName,
}
