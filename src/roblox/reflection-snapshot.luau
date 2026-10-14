--!strict

local Datatypes = require "./datatypes"
local Environment = require "./environment"
local Adapter = require "./environment-engine"
local FixtureBridge = require "./fixture-bridge"
local Reflection = require "./reflection"
local UiFakes = require "./ui-fakes"

export type Property = { datatype: string, scriptability: string, tags: { string } }
export type ClassEntry = {
	superclass: string?,
	tags: { string },
	properties: { [string]: Property },
	defaults: { [string]: unknown },
	events: { string }?,
}
export type Snapshot = {
	schemaVersion: number,
	engineVersion: string?,
	classes: { [string]: ClassEntry },
	enums: Datatypes.EnumCatalog?,
	brickColors: Datatypes.BrickColorCatalog?,
	fonts: Datatypes.FontCatalog?,
}
export type Options = {
	ui: (UiFakes.Options | false)?,
	classes: { [string]: Environment.ClassSpec }?,
	referenceClass: ((className: string, property: string) -> string?)?,
	validateProperty: ((className: string, property: string, value: unknown, operation: "set" | "poke") -> ...unknown)?,
	defaultProperty: ((className: string, property: string) -> unknown)?,
	handlerErrors: Environment.HandlerErrors?,
	computed: { [string]: Environment.Computed }?,
	undeclaredWrites: boolean?,
	undeclaredReads: ("raise" | "nil")?,
	functionDoubles: boolean?,
}

type Fields = { [string]: unknown }

local SCHEMA_VERSION = 2

local libraries: { [Snapshot]: Datatypes.Library } = {}
setmetatable(libraries, { __mode = "k" })

local function number(value: unknown): number
	if value == "inf" then
		return math.huge
	elseif value == "-inf" then
		return -math.huge
	elseif value == "nan" then
		local zero = 0
		return zero / zero
	end
	return value :: number
end

local function check(condition: boolean, message: string)
	if not condition then
		error("reflection snapshot " .. message, 3)
	end
end

local function validate(snapshot: Snapshot)
	check(type(snapshot) == "table" and snapshot.schemaVersion == SCHEMA_VERSION, "has an unsupported schema")
	check(type(snapshot.classes) == "table", "holds no classes")
	local enums: unknown = snapshot.enums
	if enums ~= nil then
		check(type(enums) == "table", "enums must be a table")
		for family, items in enums :: { [unknown]: unknown } do
			check(type(family) == "string" and type(items) == "table", "enum families must be named lists")
			for _, item in items :: { unknown } do
				local entry = item :: Fields
				check(
					type(item) == "table" and type(entry.name) == "string" and type(entry.value) == "number",
					"enum items need a name and a value: " .. tostring(family)
				)
			end
		end
	end
	local colors: unknown = snapshot.brickColors
	if colors ~= nil then
		local fields = colors :: Fields
		check(
			type(colors) == "table" and type(fields.colors) == "table" and type(fields.palette) == "table",
			"brickColors need colors and a palette"
		)
	end
	local fonts: unknown = snapshot.fonts
	if fonts ~= nil then
		check(type(fonts) == "table", "fonts must be a table")
	end
end

local function library(snapshot: Snapshot): Datatypes.Library
	local cached = libraries[snapshot]
	if cached ~= nil then
		return cached
	end
	validate(snapshot)
	local created = Datatypes.create {
		enums = snapshot.enums,
		brickColors = snapshot.brickColors,
		fonts = snapshot.fonts,
	}
	libraries[snapshot] = created
	return created
end

local function components(tagged: Fields): { number }
	local raw = tagged.v
	check(type(raw) == "table", "holds a malformed " .. tostring(tagged["$"]) .. " default")
	local out: { number } = {}
	for index, item in raw :: { unknown } do
		out[index] = number(item)
	end
	return out
end

local function enumItem(types: Datatypes.Library, family: unknown, name: unknown): unknown
	local found, value = pcall(function(): unknown
		return ((types.Enum :: unknown) :: { [string]: { [string]: unknown } })[family :: string][name :: string]
	end)
	check(found, ("names Enum.%s.%s, which its enums lack"):format(tostring(family), tostring(name)))
	return value
end

local function decodeValue(types: Datatypes.Library, value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local tagged = value :: Fields
	local kind = tagged["$"]
	if kind == "bytes" then
		return (
			string.gsub(tagged.v :: string, "%x%x", function(pair: string): string
				return string.char(tonumber(pair, 16) :: number)
			end)
		)
	elseif kind == "number" then
		return number(tagged.v)
	elseif kind == "EnumItem" then
		return enumItem(types, tagged.family, tagged.name)
	elseif kind == "BrickColor" then
		return types.BrickColor.new(tagged.v :: number)
	elseif kind == "Font" then
		return types.Font.new(
			tagged.family :: string,
			enumItem(types, "FontWeight", tagged.weight) :: Datatypes.EnumMember,
			enumItem(types, "FontStyle", tagged.style) :: Datatypes.EnumMember
		)
	elseif kind == "Content" then
		return if type(tagged.uri) == "string" then types.Content.fromUri(tagged.uri :: string) else types.Content.none
	end
	local v = components(tagged)
	if kind == "Vector3" then
		return types.Vector3.new(v[1], v[2], v[3])
	elseif kind == "Vector2" then
		return types.Vector2.new(v[1], v[2])
	elseif kind == "Vector3int16" then
		return types.Vector3int16.new(v[1], v[2], v[3])
	elseif kind == "Vector2int16" then
		return types.Vector2int16.new(v[1], v[2])
	elseif kind == "Color3" then
		return types.Color3.new(v[1], v[2], v[3])
	elseif kind == "UDim" then
		return types.UDim.new(v[1], v[2])
	elseif kind == "UDim2" then
		return types.UDim2.new(v[1], v[2], v[3], v[4])
	elseif kind == "CFrame" then
		return (types.CFrame.new :: (...number) -> unknown)(table.unpack(v, 1, 12))
	elseif kind == "Rect" then
		return types.Rect.new(v[1], v[2], v[3], v[4])
	elseif kind == "NumberRange" then
		return types.NumberRange.new(v[1], v[2])
	elseif kind == "NumberSequence" then
		local keypoints: { Datatypes.NumberSequenceKeypointValue } = {}
		for index = 1, #v, 3 do
			table.insert(keypoints, types.NumberSequenceKeypoint.new(v[index], v[index + 1], v[index + 2]))
		end
		return types.NumberSequence.new(keypoints)
	elseif kind == "ColorSequence" then
		local keypoints: { Datatypes.ColorSequenceKeypointValue } = {}
		for index = 1, #v, 4 do
			local color = types.Color3.new(v[index + 1], v[index + 2], v[index + 3])
			table.insert(keypoints, types.ColorSequenceKeypoint.new(v[index], color))
		end
		return types.ColorSequence.new(keypoints)
	end
	return error("reflection snapshot holds an unknown value tag: " .. tostring(kind), 3)
end

local function checkStrings(values: unknown, label: string): { string }
	assert(type(values) == "table", label .. " must be a list")
	local result: { string } = {}
	for _, value in values :: { unknown } do
		assert(type(value) == "string", label .. " must contain only strings")
		table.insert(result, value)
	end
	return result
end

local function database(snapshot: Snapshot): Reflection.Database
	local types = library(snapshot)
	local names: { string } = {}
	local built: { [string]: Reflection.Class } = {}
	for name, entry in snapshot.classes do
		assert(type(entry) == "table" and type(entry.properties) == "table", "reflection class is malformed: " .. name)
		table.insert(names, name)
	end
	table.sort(names)
	local function build(name: string): Reflection.Class?
		local entry = snapshot.classes[name]
		if entry == nil then
			return nil
		end
		local properties: { [string]: Reflection.Property } = {}
		for key, property in entry.properties do
			assert(type(property.datatype) == "string" and type(property.scriptability) == "string", "bad property")
			properties[key] = {
				Name = key,
				Datatype = property.datatype,
				Scriptability = property.scriptability,
				Tags = checkStrings(property.tags, name .. "." .. key .. " tags"),
			}
		end
		local defaults: { [string]: unknown } = {}
		for key, value in entry.defaults do
			defaults[key] = decodeValue(types, value)
		end
		return {
			Name = name,
			Superclass = entry.superclass,
			Properties = properties,
			DefaultProperties = defaults,
			Tags = checkStrings(entry.tags, name .. " tags"),
			Events = if entry.events ~= nil then checkStrings(entry.events, name .. " events") else nil,
		}
	end
	local self: Reflection.Database
	self = {
		GetClassNames = function(): { string }
			return table.clone(names)
		end,
		GetClass = function(_: Reflection.Database, name: string): Reflection.Class?
			local cached = built[name]
			if cached ~= nil then
				return cached
			end
			local fresh = build(name)
			if fresh ~= nil then
				built[name] = fresh
			end
			return fresh
		end,
	}
	return self
end

local function engineLibrary(types: Datatypes.Library): Adapter.Library
	return ({ typeName = Environment.typeName, datatypes = types } :: unknown) :: Adapter.Library
end

local function bridge(snapshot: Snapshot, options: Options?): FixtureBridge.Bridge
	local settings: Options = options or {}
	return FixtureBridge.create {
		database = database(snapshot),
		typeName = Environment.typeName,
		enumType = Datatypes.enumType,
		library = engineLibrary(library(snapshot)),
		classes = settings.classes,
		referenceClass = settings.referenceClass,
		validateProperty = settings.validateProperty,
		defaultProperty = settings.defaultProperty,
		handlerErrors = settings.handlerErrors,
		computed = settings.computed,
		undeclaredWrites = settings.undeclaredWrites,
		undeclaredReads = settings.undeclaredReads,
		functionDoubles = settings.functionDoubles,
		ui = settings.ui,
	}
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	database = database,
	library = library,
	engineLibrary = engineLibrary,
	bridge = bridge,
}
