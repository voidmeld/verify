--!strict

type Read = (unknown, string) -> unknown
type Host = { read: Read, components: (unknown) -> { number } }

local function numeric(value: unknown): number
	assert(type(value) == "number")
	return value
end

local function text(value: unknown): string
	assert(type(value) == "string")
	return value
end

local function number(value: unknown): unknown
	local magnitude = value
	if magnitude ~= magnitude then
		return { ["$"] = "number", v = "nan" }
	elseif magnitude == math.huge then
		return { ["$"] = "number", v = "inf" }
	elseif magnitude == -math.huge then
		return { ["$"] = "number", v = "-inf" }
	end
	return magnitude
end

local function numbers(field: Read, value: unknown, keys: { string }): { number }
	local out: { number } = {}
	for index, key in keys do
		out[index] = numeric(field(value, key))
	end
	return out
end

local function enumName(field: Read, value: unknown): string
	return text(field(value, "Name"))
end

local function sequence(field: Read, value: unknown, read: (unknown) -> { number }): { number }
	local out: { number } = {}
	local keypoints = field(value, "Keypoints")
	assert(type(keypoints) == "table")
	for _, keypoint in keypoints do
		for _, component in read(keypoint) do
			table.insert(out, component)
		end
	end
	return out
end

local function encode(value: unknown, kind: string, host: Host): unknown
	local field = host.read
	if kind == "number" then
		return number(value)
	elseif kind == "string" then
		local text = text(value)
		if utf8.len(text) == nil then
			return {
				["$"] = "bytes",
				v = (string.gsub(text, ".", function(character: string): string
					return string.format("%02x", string.byte(character))
				end)),
			}
		end
		return text
	elseif kind == "boolean" then
		return value
	elseif kind == "Vector3" or kind == "Vector3int16" then
		return { ["$"] = kind, v = numbers(field, value, { "X", "Y", "Z" }) }
	elseif kind == "Vector2" or kind == "Vector2int16" then
		return { ["$"] = kind, v = numbers(field, value, { "X", "Y" }) }
	elseif kind == "Color3" then
		return { ["$"] = kind, v = numbers(field, value, { "R", "G", "B" }) }
	elseif kind == "UDim" then
		return { ["$"] = kind, v = numbers(field, value, { "Scale", "Offset" }) }
	elseif kind == "UDim2" then
		local x, y = field(value, "X"), field(value, "Y")
		return {
			["$"] = kind,
			v = {
				field(x, "Scale"),
				field(x, "Offset"),
				field(y, "Scale"),
				field(y, "Offset"),
			},
		}
	elseif kind == "CFrame" then
		return { ["$"] = kind, v = host.components(value) }
	elseif kind == "Rect" then
		local min, max = field(value, "Min"), field(value, "Max")
		return {
			["$"] = kind,
			v = {
				field(min, "X"),
				field(min, "Y"),
				field(max, "X"),
				field(max, "Y"),
			},
		}
	elseif kind == "NumberRange" then
		return { ["$"] = kind, v = numbers(field, value, { "Min", "Max" }) }
	elseif kind == "NumberSequence" then
		return {
			["$"] = kind,
			v = sequence(field, value, function(keypoint: unknown): { number }
				return numbers(field, keypoint, { "Time", "Value", "Envelope" })
			end),
		}
	elseif kind == "ColorSequence" then
		return {
			["$"] = kind,
			v = sequence(field, value, function(keypoint: unknown): { number }
				local color = field(keypoint, "Value")
				return {
					numeric(field(keypoint, "Time")),
					numeric(field(color, "R")),
					numeric(field(color, "G")),
					numeric(field(color, "B")),
				}
			end),
		}
	elseif kind == "BrickColor" then
		return { ["$"] = kind, v = field(value, "Number") }
	elseif kind == "Font" then
		return {
			["$"] = kind,
			family = field(value, "Family"),
			weight = enumName(field, field(value, "Weight")),
			style = enumName(field, field(value, "Style")),
		}
	elseif kind == "Content" then
		local source = enumName(field, field(value, "SourceType"))
		if source == "None" then
			return { ["$"] = kind }
		elseif source == "Uri" then
			return { ["$"] = kind, uri = field(value, "Uri") }
		end
		return nil
	elseif kind == "EnumItem" then
		local family = string.gsub(tostring(field(value, "EnumType")), "^Enum%.", "")
		return { ["$"] = kind, family = family, name = enumName(field, value) }
	end
	return nil
end

local ESCAPES: { [string]: string } = {
	["\\"] = "\\\\",
	['"'] = '\\"',
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function quote(value: string): string
	local escaped = string.gsub(value, '[%c"\\]', function(character: string): string
		return ESCAPES[character] or string.format("\\u%04x", string.byte(character))
	end)
	return '"' .. escaped .. '"'
end

local function serialize(value: unknown): string
	if type(value) == "string" then
		return quote(value)
	elseif type(value) == "number" then
		local whole = value
		if whole ~= whole then
			return '"nan"'
		elseif whole == math.huge then
			return '"inf"'
		elseif whole == -math.huge then
			return '"-inf"'
		end
		return if whole % 1 == 0 and math.abs(whole) < 2 ^ 53
			then string.format("%d", whole)
			else string.format("%.17g", whole)
	elseif type(value) == "boolean" then
		return tostring(value)
	end
	assert(type(value) == "table")
	local entries = value
	if #entries > 0 or next(entries) == nil then
		local items: { string } = {}
		for index, item in entries do
			assert(type(index) == "number")
			items[index] = serialize(item)
		end
		return "[" .. table.concat(items, ",") .. "]"
	end
	local keys: { string } = {}
	local fields: { [string]: unknown } = {}
	for key, item in entries do
		local name = text(key)
		table.insert(keys, name)
		fields[name] = item
	end
	table.sort(keys)
	local pieces: { string } = {}
	for _, key in keys do
		table.insert(pieces, quote(key) .. ":" .. serialize(fields[key]))
	end
	return "{" .. table.concat(pieces, ",") .. "}"
end

return { encode = encode, serialize = serialize }
