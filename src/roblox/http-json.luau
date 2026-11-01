--!strict
local Vm = require "./value"

local function encode(value: Vm.Value, primitive: (unknown) -> string, typeName: (unknown) -> string): string
	local active: { [unknown]: boolean } = {}
	local visit: (Vm.Value) -> string
	visit = function(current: Vm.Value): string
		local kind = typeName(current)
		if kind == "string" or kind == "number" or kind == "boolean" or kind == "buffer" then
			return primitive(current)
		end
		if kind ~= "table" then
			return "null"
		end
		assert(not active[current], "tables cannot be cyclic")
		active[current] = true
		assert(type(current) == "table", "expected JSON table")
		local values = current
		local count = rawlen(values)
		local parts: { string } = {}
		local result: string
		if count > 0 or next(values) == nil then
			for index = 1, count do
				table.insert(parts, visit(rawget(values, index)))
			end
			result = "[" .. table.concat(parts, ",") .. "]"
		else
			for key, item in next, values do
				local name: string
				if type(key) == "string" then
					name = key
				elseif type(key) == "number" then
					name = string.format("%d", key)
				else
					error("unsupported_json_key: " .. typeName(key), 0)
				end
				table.insert(parts, primitive(name) .. ":" .. visit(item))
			end
			result = "{" .. table.concat(parts, ",") .. "}"
		end
		active[current] = nil
		return result
	end
	return visit(value)
end

return { encode = encode }
