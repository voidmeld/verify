--!strict

local Environment = require "../roblox/environment"
local Adapter = require "../roblox/environment-engine"
local FixtureBridge = require "../roblox/fixture-bridge"
local Reflection = require "../roblox/reflection"
local UiFakes = require "../roblox/ui-fakes"

export type Native<V2, V3, C3, U1, U2, CF> = {
	getReflectionDatabase: () -> Reflection.Database,
	Vector2: { new: (number, number) -> V2 },
	Vector3: { new: (number, number, number) -> V3 },
	Color3: { new: (number, number, number) -> C3 },
	UDim: { new: (number, number) -> U1 },
	UDim2: { new: (number, number, number, number) -> U2 },
	CFrame: { new: (...number) -> CF },
	Instance: { new: (className: string) -> unknown }?,
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

local load = require :: (string) -> unknown

local function enumType(value: unknown): string
	return tostring((value :: { EnumType: unknown }).EnumType)
end

local function nativeDefault<V2, V3, C3, U1, U2, CF>(
	native: Native<V2, V3, C3, U1, U2, CF>
): ((className: string, property: string) -> unknown)?
	local constructor = native.Instance
	if constructor == nil then
		return nil
	end
	local samples: { [string]: unknown } = {}
	local absent = {}
	return function(className: string, property: string): unknown
		local sample = samples[className]
		if sample == nil then
			local ok, created = pcall(constructor.new, className)
			sample = if ok then created else absent
			samples[className] = sample
		end
		if sample == absent then
			return nil
		end
		local ok, value = pcall(function(): unknown
			return (sample :: { [string]: unknown })[property]
		end)
		local kind: string = typeof(value)
		if not ok or kind == "Instance" or kind == "function" then
			return nil
		end
		return value
	end
end

local function createFrom<V2, V3, C3, U1, U2, CF>(native: Native<V2, V3, C3, U1, U2, CF>, options: Options?): FixtureBridge.Bridge
	local settings: Options = options or {}
	local library: Adapter.Library<V2, V3, C3, U1, U2, CF> = {
		typeName = function(value: unknown): string
			return typeof(value)
		end,
		datatypes = {
			Vector2 = native.Vector2,
			Vector3 = native.Vector3,
			Color3 = native.Color3,
			UDim = native.UDim,
			UDim2 = native.UDim2,
			CFrame = native.CFrame,
		},
	}
	return FixtureBridge.create {
		database = native.getReflectionDatabase(),
		typeName = function(value: unknown): string
			return typeof(value)
		end,
		enumType = enumType,
		library = library,
		classes = settings.classes,
		referenceClass = settings.referenceClass,
		validateProperty = settings.validateProperty,
		defaultProperty = settings.defaultProperty or nativeDefault(native),
		handlerErrors = settings.handlerErrors,
		computed = settings.computed,
		undeclaredWrites = settings.undeclaredWrites,
		undeclaredReads = settings.undeclaredReads,
		functionDoubles = settings.functionDoubles,
		ui = settings.ui,
	}
end

local function create(options: Options?): FixtureBridge.Bridge
	local native = load "@lune/roblox" :: Native<unknown, unknown, unknown, unknown, unknown, unknown>
	return createFrom(native, options)
end

return {
	create = create,
	createFrom = createFrom,
}
