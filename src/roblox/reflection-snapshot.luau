--!strict

local Datatypes = require "./datatypes"
local Environment = require "./environment"
local FixtureBridge = require "./fixture-bridge"
local Reflection = require "./reflection"
local UiFakes = require "./ui-fakes"

export type Property = { datatype: string, scriptability: string, tags: { string } }
export type ClassEntry = {
	superclass: string?,
	tags: { string },
	properties: { [string]: Property },
	defaults: { [string]: unknown },
}
export type Snapshot = {
	schemaVersion: number,
	classes: { [string]: ClassEntry },
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

local SCHEMA_VERSION = 1

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

local function decodeValue(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end
	local tagged = value :: { [string]: unknown }
	local kind = tagged["$"]
	if kind == "bytes" then
		return (
			string.gsub(tagged.v :: string, "%x%x", function(pair: string): string
				return string.char(tonumber(pair, 16) :: number)
			end)
		)
	end
	if kind == "number" then
		return number(tagged.v)
	end
	local raw = tagged.v :: { unknown }?
	local v: { number }? = nil
	if raw ~= nil then
		v = {}
		for index, item in raw do
			(v :: { number })[index] = number(item)
		end
	end
	if kind == "Vector3" and v ~= nil then
		return Datatypes.Vector3.new(v[1], v[2], v[3])
	elseif kind == "Vector2" and v ~= nil then
		return Datatypes.Vector2.new(v[1], v[2])
	elseif kind == "Color3" and v ~= nil then
		return Datatypes.Color3.new(v[1], v[2], v[3])
	elseif kind == "UDim" and v ~= nil then
		return Datatypes.UDim.new(v[1], v[2])
	elseif kind == "UDim2" and v ~= nil then
		return Datatypes.UDim2.new(v[1], v[2], v[3], v[4])
	elseif kind == "CFrame" and v ~= nil then
		return (Datatypes.CFrame.new :: (...number) -> unknown)(table.unpack(v, 1, 12))
	elseif kind == "EnumItem" then
		return Datatypes.Enum[tagged.family :: string][tagged.name :: string]
	end
	error("reflection snapshot holds an unknown value tag: " .. tostring(kind), 3)
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
	assert(type(snapshot) == "table" and snapshot.schemaVersion == SCHEMA_VERSION, "unsupported reflection snapshot")
	assert(type(snapshot.classes) == "table", "reflection snapshot holds no classes")
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
			defaults[key] = decodeValue(value)
		end
		return {
			Name = name,
			Superclass = entry.superclass,
			Properties = properties,
			DefaultProperties = defaults,
			Tags = checkStrings(entry.tags, name .. " tags"),
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

local function bridge(snapshot: Snapshot, options: Options?): FixtureBridge.Bridge
	local settings: Options = options or {}
	return FixtureBridge.create {
		database = database(snapshot),
		typeName = Environment.typeName,
		enumType = Datatypes.enumType,
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
	bridge = bridge,
}
