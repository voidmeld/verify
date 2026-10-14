--!strict

local Reflection = require "../roblox/reflection"
local Encoding = require "../roblox/reflection-encoding"
local Snapshot = require "../roblox/reflection-snapshot"

export type Native = {
	getReflectionDatabase: () -> Reflection.Database,
}

export type Options = {
	classes: { string }?,
	typeName: (unknown) -> string,
}

local load = require :: (string) -> unknown

local ENCODED: { [string]: boolean } = {
	boolean = true,
	number = true,
	string = true,
	Vector3 = true,
	Vector2 = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	EnumItem = true,
}

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
			local kind = options.typeName(value)
			local encoded = if ENCODED[kind] then Encoding.encode(value, kind) else nil
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

local function create(options: { classes: { string }? }?): Snapshot.Snapshot
	local native = load "@lune/roblox" :: Native
	return export(native, {
		classes = if options ~= nil then options.classes else nil,
		typeName = function(value: unknown): string
			return typeof(value)
		end,
	})
end

return { export = export, create = create, serialize = Encoding.serialize }
