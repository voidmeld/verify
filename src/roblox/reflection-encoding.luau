--!strict

type Fields = { [string]: unknown }

local function number(value: unknown): unknown
	local magnitude = value :: number
	if magnitude ~= magnitude then
		return { ["$"] = "number", v = "nan" }
	elseif magnitude == math.huge then
		return { ["$"] = "number", v = "inf" }
	elseif magnitude == -math.huge then
		return { ["$"] = "number", v = "-inf" }
	end
	return magnitude
end

local function field(value: unknown, key: string): unknown
	return (value :: Fields)[key]
end

local function numbers(value: unknown, keys: { string }): { number }
	local out: { number } = {}
	for index, key in keys do
		out[index] = field(value, key) :: number
	end
	return out
end

local function enumName(value: unknown): string
	return field(value, "Name") :: string
end

local function sequence(value: unknown, read: (unknown) -> { number }): { number }
	local out: { number } = {}
	for _, keypoint in field(value, "Keypoints") :: { unknown } do
		for _, component in read(keypoint) do
			table.insert(out, component)
		end
	end
	return out
end

local function encode(value: unknown, kind: string): unknown
	if kind == "number" then
		return number(value)
	elseif kind == "string" then
		local text = value :: string
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
		return { ["$"] = kind, v = numbers(value, { "X", "Y", "Z" }) }
	elseif kind == "Vector2" or kind == "Vector2int16" then
		return { ["$"] = kind, v = numbers(value, { "X", "Y" }) }
	elseif kind == "Color3" then
		return { ["$"] = kind, v = numbers(value, { "R", "G", "B" }) }
	elseif kind == "UDim" then
		return { ["$"] = kind, v = numbers(value, { "Scale", "Offset" }) }
	elseif kind == "UDim2" then
		local x, y = field(value, "X"), field(value, "Y")
		return {
			["$"] = kind,
			v = {
				field(x, "Scale") :: number,
				field(x, "Offset") :: number,
				field(y, "Scale") :: number,
				field(y, "Offset") :: number,
			},
		}
	elseif kind == "CFrame" then
		return { ["$"] = kind, v = { (field(value, "GetComponents") :: (unknown) -> ...number)(value) } }
	elseif kind == "Rect" then
		local min, max = field(value, "Min"), field(value, "Max")
		return {
			["$"] = kind,
			v = {
				field(min, "X") :: number,
				field(min, "Y") :: number,
				field(max, "X") :: number,
				field(max, "Y") :: number,
			},
		}
	elseif kind == "NumberRange" then
		return { ["$"] = kind, v = numbers(value, { "Min", "Max" }) }
	elseif kind == "NumberSequence" then
		return {
			["$"] = kind,
			v = sequence(value, function(keypoint: unknown): { number }
				return numbers(keypoint, { "Time", "Value", "Envelope" })
			end),
		}
	elseif kind == "ColorSequence" then
		return {
			["$"] = kind,
			v = sequence(value, function(keypoint: unknown): { number }
				local color = field(keypoint, "Value")
				return {
					field(keypoint, "Time") :: number,
					field(color, "R") :: number,
					field(color, "G") :: number,
					field(color, "B") :: number,
				}
			end),
		}
	elseif kind == "BrickColor" then
		return { ["$"] = kind, v = field(value, "Number") }
	elseif kind == "Font" then
		return {
			["$"] = kind,
			family = field(value, "Family"),
			weight = enumName(field(value, "Weight")),
			style = enumName(field(value, "Style")),
		}
	elseif kind == "Content" then
		local source = enumName(field(value, "SourceType"))
		if source == "None" then
			return { ["$"] = kind }
		elseif source == "Uri" then
			return { ["$"] = kind, uri = field(value, "Uri") }
		end
		return nil
	elseif kind == "EnumItem" then
		local family = string.gsub(tostring(field(value, "EnumType")), "^Enum%.", "")
		return { ["$"] = kind, family = family, name = enumName(value) }
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
	local kind = type(value)
	if kind == "string" then
		return quote(value :: string)
	elseif kind == "number" then
		local whole = value :: number
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
	elseif kind == "boolean" then
		return tostring(value)
	end
	local entries = value :: { [unknown]: unknown }
	if #entries > 0 or next(entries) == nil then
		local items: { string } = {}
		for index, item in entries :: { unknown } do
			items[index] = serialize(item)
		end
		return "[" .. table.concat(items, ",") .. "]"
	end
	local keys: { string } = {}
	for key in entries do
		table.insert(keys, key :: string)
	end
	table.sort(keys)
	local pieces: { string } = {}
	for _, key in keys do
		table.insert(pieces, quote(key) .. ":" .. serialize(entries[key]))
	end
	return "{" .. table.concat(pieces, ",") .. "}"
end

return { encode = encode, serialize = serialize }
