--!strict

local Reflection = require "../roblox/reflection"
local Snapshot = require "../roblox/reflection-snapshot"

export type Native = {
	getReflectionDatabase: () -> Reflection.Database,
}

export type Options = {
	classes: { string }?,
	typeName: (unknown) -> string,
}

local load = require :: (string) -> unknown

local function number(value: unknown): number
	return value :: number
end

local function encode(value: unknown, kind: string): unknown
	if kind == "number" then
		local magnitude = value :: number
		if magnitude ~= magnitude then
			return { ["$"] = "number", v = "nan" }
		elseif magnitude == math.huge then
			return { ["$"] = "number", v = "inf" }
		elseif magnitude == -math.huge then
			return { ["$"] = "number", v = "-inf" }
		end
		return value
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
	end
	local fields = value :: { [string]: unknown }
	if kind == "Vector3" then
		return { ["$"] = kind, v = { number(fields.X), number(fields.Y), number(fields.Z) } }
	elseif kind == "Vector2" then
		return { ["$"] = kind, v = { number(fields.X), number(fields.Y) } }
	elseif kind == "Color3" then
		return { ["$"] = kind, v = { number(fields.R), number(fields.G), number(fields.B) } }
	elseif kind == "UDim" then
		return { ["$"] = kind, v = { number(fields.Scale), number(fields.Offset) } }
	elseif kind == "UDim2" then
		local x = fields.X :: { [string]: unknown }
		local y = fields.Y :: { [string]: unknown }
		return { ["$"] = kind, v = { number(x.Scale), number(x.Offset), number(y.Scale), number(y.Offset) } }
	elseif kind == "CFrame" then
		return { ["$"] = kind, v = { (fields.GetComponents :: (unknown) -> ...number)(value) } }
	elseif kind == "EnumItem" then
		local family = string.gsub(tostring(fields.EnumType), "^Enum%.", "")
		return { ["$"] = kind, family = family, name = fields.Name }
	end
	return nil
end

local function sorted(values: { string }): { string }
	local copy = table.clone(values)
	table.sort(copy)
	return copy
end

local function export(native: Native, options: Options): Snapshot.Snapshot
	local database = native.getReflectionDatabase()
	local wanted: { [string]: boolean } = {}
	local selected = options.classes
	if selected ~= nil then
		for _, name in selected do
			local current: string? = name
			while current ~= nil and not wanted[current] do
				local class = database:GetClass(current)
				assert(class ~= nil, "reflection class missing: " .. current)
				wanted[current] = true
				current = class.Superclass
			end
		end
	else
		for _, name in database:GetClassNames() do
			wanted[name] = true
		end
	end
	local classes: { [string]: Snapshot.ClassEntry } = {}
	for name in wanted do
		local class = database:GetClass(name) :: Reflection.Class
		local properties: { [string]: Snapshot.Property } = {}
		for key, property in class.Properties do
			properties[key] = {
				datatype = property.Datatype,
				scriptability = property.Scriptability,
				tags = sorted(property.Tags),
			}
		end
		local defaults: { [string]: unknown } = {}
		for key, value in class.DefaultProperties do
			local encoded = encode(value, options.typeName(value))
			if encoded ~= nil then
				defaults[key] = encoded
			end
		end
		classes[name] = {
			superclass = class.Superclass,
			tags = sorted(class.Tags),
			properties = properties,
			defaults = defaults,
		}
	end
	return { schemaVersion = Snapshot.SCHEMA_VERSION, classes = classes }
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
	local table_ = value :: { [unknown]: unknown }
	if #table_ > 0 or next(table_) == nil then
		local items: { string } = {}
		for index, item in table_ :: { unknown } do
			items[index] = serialize(item)
		end
		return "[" .. table.concat(items, ",") .. "]"
	end
	local keys: { string } = {}
	for key in table_ do
		table.insert(keys, key :: string)
	end
	table.sort(keys)
	local pieces: { string } = {}
	for _, key in keys do
		table.insert(pieces, quote(key) .. ":" .. serialize(table_[key]))
	end
	return "{" .. table.concat(pieces, ",") .. "}"
end

local function create(options: { classes: { string }? }?): Snapshot.Snapshot
	local native = load "@lune/roblox" :: Native
	return export(native, {
		classes = if options ~= nil then options.classes else nil,
		typeName = function(value: unknown): string
			return typeof(value)
		end,
	})
end

return { export = export, create = create, serialize = serialize }
