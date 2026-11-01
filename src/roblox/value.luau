--!strict

local function opaque(value: unknown)
	assert(type(value) ~= "function" and type(value) ~= "table", "expected an opaque VM value")
	return value
end

export type Value = typeof(opaque(nil)) | { [unknown]: Value } | ((...unknown) -> ...Value)

local held: unknown
local slot: { Value } = setmetatable({}, {
	__index = function(): unknown
		return held
	end,
})

local function value(item: unknown): Value
	held = item
	local result = slot[1]
	held = nil
	return result
end

local function invoke(value: Value, ...: unknown): ...Value
	assert(type(value) == "function", "expected a VM function")
	return value(...)
end

local function read(value: Value, key: unknown): Value
	assert(type(value) == "table", "expected a VM table")
	return value[key]
end

local function write(value: Value, key: unknown, item: Value)
	assert(type(value) == "table", "expected a VM table")
	value[key] = item
end

return { invoke = invoke, read = read, value = value, write = write }
