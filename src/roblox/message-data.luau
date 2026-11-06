--!strict

local D = require "./datatypes"

local function copy(value: unknown, values: boolean, active: { [unknown]: boolean }?): unknown
	local kind = D.typeof(value)
	if kind ~= type(value) then
		assert(values and D.isAttributeType(kind) and kind ~= "Instance", "unsupported payload value")
		return value
	end
	if type(value) == "table" then
		local path = active or {}
		assert(not path[value], "payload must not contain cycles")
		path[value] = true
		local result: { [string | number]: unknown } = {}
		local keyType: string? = nil
		for key, child in value do
			assert(type(key) == "string" or type(key) == "number", "payload keys must be strings or numbers")
			assert(keyType == nil or keyType == type(key), "payload must not mix array and dictionary keys")
			keyType = type(key)
			if type(key) == "number" then
				assert(key >= 1 and key % 1 == 0, "payload array keys must be positive integers")
			end
			result[key] = copy(child, values, path)
		end
		if keyType == "number" then
			local count = 0
			for _ in result do
				count += 1
			end
			assert(#result == count, "payload arrays must not have holes")
		end
		path[value] = nil
		return result
	end
	if type(value) == "number" then
		assert(value == value and math.abs(value) < math.huge, "payload numbers must be finite")
		return value
	end
	if value == nil or type(value) == "boolean" or type(value) == "string" then
		return value
	end
	error("unsupported payload value", 2)
end

return { copy = copy }
