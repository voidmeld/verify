--!strict

local Environment = require "./environment"

export type Property = { Name: string, Datatype: string, Scriptability: string, Tags: { string } }
export type Class = {
	Name: string,
	Superclass: string?,
	Properties: { [string]: Property },
	DefaultProperties: { [string]: unknown },
	Tags: { string },
}
export type Database = { GetClassNames: (Database) -> { string }, GetClass: (Database, string) -> Class? }
export type Options = {
	database: Database,
	typeName: (unknown) -> string,
	enumType: ((unknown) -> string)?,
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

local function create(options: Options): Environment.Environment
	local database = options.database
	local definitions: { [string]: Environment.ClassSpec } = {}
	local properties: { [string]: { [string]: Property } } = {}
	local defaults: { [string]: { [string]: unknown } } = {}
	local active: { [string]: boolean } = {}
	local function resolve(name: string)
		if definitions[name] then
			return
		end
		assert(not active[name], "reflection inheritance cycle: " .. name)
		active[name] = true
		local class = database:GetClass(name)
		assert(class ~= nil, "reflection class missing: " .. name)
		local super = class.Superclass
		if super then
			resolve(super)
		end
		local members = if super then table.clone(properties[super]) else {}
		local values = if super then table.clone(defaults[super]) else {}
		local declared: { [string]: unknown } = {}
		for key, property in class.Properties do
			if key ~= "ClassName" and key ~= "Parent" then
				members[key] = property
				declared[key] = false
			end
		end
		for key, value in class.DefaultProperties do
			values[key] = value
		end
		definitions[name] = {
			super = super,
			creatable = table.find(class.Tags, "NotCreatable") == nil and table.find(class.Tags, "Service") == nil,
			properties = declared,
		}
		properties[name], defaults[name] = members, values
		active[name] = nil
	end
	for _, name in database:GetClassNames() do
		resolve(name)
	end
	local overlays: { [string]: Environment.ClassSpec } = options.classes or {}
	for name, overlay in overlays do
		local base = definitions[name]
		assert(base ~= nil, "reflection overlay requires a known class: " .. name)
		local merged = table.clone(base)
		if overlay.creatable ~= nil then
			merged.creatable = overlay.creatable
		end
		merged.events, merged.methods = overlay.events, overlay.methods
		local declared = table.clone(base.properties or {})
		local added: { [string]: unknown } = overlay.properties or {}
		for key, value in added do
			declared[key] = value
		end
		merged.properties = declared
		definitions[name] = merged
	end
	local numeric = {
		float = true,
		double = true,
		int = true,
		int64 = true,
		number = true,
		Float32 = true,
		Float64 = true,
		Int32 = true,
		Int64 = true,
	}
	local doubles: { [string]: boolean } = {}
	local environment = Environment.create {
		builtins = false,
		classes = definitions,
		defaultProperty = function(className, key, fallback)
			if key == "Name" then
				return className
			end
			local declared = properties[className]
			if declared ~= nil and declared[key] then
				local value = defaults[className][key]
				if value ~= nil then
					return value
				end
				if fallback == nil and options.defaultProperty ~= nil then
					return options.defaultProperty(className, key)
				end
			end
			return fallback
		end,
		handlerErrors = options.handlerErrors,
		computed = options.computed,
		undeclaredWrites = options.undeclaredWrites,
		undeclaredReads = options.undeclaredReads,
		functionDoubles = options.functionDoubles,
		validateProperty = function(className, key, value, operation)
			if key == "Parent" then
				if options.validateProperty then
					return options.validateProperty(className, key, value, operation)
				end
				return nil
			end
			local known = if doubles[className] then nil else properties[className]
			local property = if known ~= nil then known[key] else nil
			if not property then
				if options.validateProperty then
					return options.validateProperty(className, key, value, operation)
				end
				return nil
			end
			if operation == "set" then
				assert(
					table.find(property.Tags, "ReadOnly") == nil
						and property.Scriptability ~= "Read"
						and property.Scriptability ~= "None",
					"read-only property: " .. key
				)
			end
			local expected = property.Datatype
			local actual = if Environment.isInstance(value) then "Instance" else options.typeName(value)
			local valid = actual == expected or (expected == "String" and actual == "string")
			if numeric[expected] then
				valid = type(value) == "number"
			elseif expected == "bool" or expected == "Bool" then
				valid = type(value) == "boolean"
			elseif expected == "Content" or expected == "ContentId" then
				valid = actual == "string" or actual == expected
			elseif expected == "Ref" then
				valid = value == nil or Environment.isInstance(value)
			elseif expected:sub(1, 5) == "Enum." then
				local enumType = if actual == "EnumItem" and options.enumType then options.enumType(value) else ""
				valid = enumType == expected or enumType == expected:sub(6)
			elseif definitions[expected] then
				valid = value == nil
					or (Environment.isInstance(value) and (value :: Environment.Instance):IsA(expected))
			end
			if valid and expected == "Ref" and value ~= nil and options.referenceClass then
				local target = options.referenceClass(className, key)
				if target then
					valid = (value :: Environment.Instance):IsA(target)
				end
			end
			assert(valid, className .. "." .. key .. " requires " .. expected .. ", received " .. actual)
			if options.validateProperty then
				return options.validateProperty(className, key, value, operation)
			end
			return nil
		end,
	}
	local define = environment.defineClass
	environment.defineClass = function(className, spec, defineOptions)
		doubles[className] = true
		define(className, spec, defineOptions)
	end
	return environment
end
return { create = create }
