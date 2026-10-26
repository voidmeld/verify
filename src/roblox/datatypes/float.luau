--!strict

local slot = buffer.create(4)

local function f32(value: number): number
	buffer.writef32(slot, 0, value)
	return buffer.readf32(slot, 0)
end

local function int32(value: number): number
	local whole = if value >= 0 then math.floor(value) else math.ceil(value)
	if whole ~= whole or whole >= 2 ^ 31 or whole < -2 ^ 31 then
		return -2 ^ 31
	end
	return whole
end

local function int16(value: number): number
	local whole = int32(value) % 65536
	return if whole >= 32768 then whole - 65536 else whole
end

local function special(value: number, upper: boolean): string?
	local text = if value ~= value
		then "nan"
		elseif value == math.huge then "inf"
		elseif value == -math.huge then "-inf"
		else nil
	if text ~= nil and upper then
		return string.upper(text)
	end
	return text
end

local function general(value: number, digits: number, upper: boolean?): string
	return special(value, upper == true) or string.format("%." .. digits .. "g", value)
end

local function shortest(value: number): string
	return special(value, false) or tostring(value)
end

local function coerce(value: unknown, position: number): number
	if value == nil then
		return 0
	end
	local converted = tonumber(value)
	if converted == nil then
		error(("invalid argument #%d to 'new' (number expected, got %s)"):format(position, type(value)), 3)
	end
	return converted
end

return {
	f32 = f32,
	int32 = int32,
	int16 = int16,
	general = general,
	shortest = shortest,
	coerce = coerce,
}
