--!strict

local Types = require "./environment-types"
local Names = require "./datatypes/names"
local BASIC_CLASSES = require "./environment-classes"
type Instance = Types.Instance
type ClassSpec<P = { [string]: unknown }, M = { [string]: unknown }> = Types.ClassSpec<P, M>
type Resolved = Types.Resolved
type DefineOptions = Types.DefineOptions
type Computed = Types.Computed
local metatableOf = (getmetatable :: unknown) :: (unknown) -> unknown

local UNIVERSAL_EVENTS: { string } = {
	"Changed",
	"ChildAdded",
	"ChildRemoved",
	"Destroying",
	"AttributeChanged",
	"DescendantAdded",
	"DescendantRemoving",
	"AncestryChanged",
}

local function create(settings: Types.Options)
	local specs: { [string]: ClassSpec } = {}
	local resolved: { [string]: Resolved } = {}
	local computedLookups: { [string]: { [string]: { get: ((object: Instance) -> unknown)?, writable: boolean } } } = {}
	local function defineClass<P, M>(className: string, spec: ClassSpec<P, M>, defineOptions: DefineOptions?)
		if type(className) ~= "string" or className == "" then
			error("class name must be a non-empty string", 2)
		end
		if specs[className] ~= nil and not (defineOptions ~= nil and defineOptions.replace == true) then
			error(("class %q is already defined"):format(className), 2)
		end
		specs[className] = (spec :: unknown) :: ClassSpec
		table.clear(resolved)
		table.clear(computedLookups)
	end

	if settings.builtins ~= false then
		for className, spec in BASIC_CLASSES do
			specs[className] = spec
		end
	end
	local extraClasses: { [string]: ClassSpec } = settings.classes or {}
	for className, spec in extraClasses do
		specs[className] = spec
	end

	local function resolve(className: string): Resolved?
		local cached = resolved[className]
		if cached ~= nil then
			return cached
		end
		local spec = specs[className]
		if spec == nil then
			return nil
		end
		local parent: Resolved? = if spec.super ~= nil then resolve(spec.super) else nil
		if spec.super ~= nil and parent == nil then
			error(("class %q extends undefined class %q"):format(className, spec.super), 3)
		end
		local result: Resolved = {
			instance = className == "Instance" or (if parent ~= nil then parent.instance else className ~= "Object"),
			creatable = if spec.creatable ~= nil then spec.creatable else true,
			access = if parent ~= nil then table.clone(parent.access) else {},
			properties = if parent ~= nil then table.clone(parent.properties) else {},
			events = if parent ~= nil then table.clone(parent.events) else {},
			methods = if parent ~= nil then table.clone(parent.methods) else {},
		}
		if (parent == nil and result.instance) or className == "Instance" then
			result.properties.Name = false
			result.properties.Archivable = true
			for _, event in UNIVERSAL_EVENTS do
				result.events[event] = true
			end
		elseif parent == nil then
			result.events.Changed = true
		end
		local declared: { [string]: unknown } = spec.properties or {}
		for key, default in declared do
			result.properties[key] = default
		end
		local declaredEvents: { string } = spec.events or {}
		for _, event in declaredEvents do
			result.events[event] = true
		end
		local declaredMethods: { [string]: unknown } = spec.methods or {}
		local declaredAccess: { [string]: "read" | "write" | "none" | "callback" } = spec.access or {}
		for key in declaredAccess do
			result.access[key] = declaredAccess[key]
		end
		for key, method in declaredMethods do
			result.methods[key] = method
		end
		resolved[className] = result
		return result
	end

	local function isA(className: string, target: string): boolean
		local walk: string? = className
		while walk ~= nil do
			if walk == target then
				return true
			end
			local spec = specs[walk]
			walk = if spec ~= nil then spec.super else nil
		end
		return false
	end

	local function lookupComputed(
		getters: { [string]: Computed },
		className: string,
		key: string
	): (((object: Instance) -> unknown)?, boolean)
		local walk: string? = className
		while walk ~= nil do
			local entry = getters[walk .. "." .. key]
			if entry ~= nil then
				if type(entry) == "function" then
					return entry, false
				end
				return entry.get, entry.writable == true
			end
			local spec = specs[walk]
			walk = if spec ~= nil then spec.super else nil
		end
		return nil, false
	end
	local function computedEntry(className: string, key: string): (((object: Instance) -> unknown)?, boolean)
		local getters = settings.computed
		if getters == nil or (next(getters) == nil and metatableOf(getters) == nil) then
			return nil, false
		end
		if not table.isfrozen(getters) then
			return lookupComputed(getters, className, key)
		end
		local byKey = computedLookups[className]
		if byKey == nil then
			byKey = {}
			computedLookups[className] = byKey
		end
		local found = byKey[key]
		if found == nil then
			local get, writable = lookupComputed(getters, className, key)
			found = { get = get, writable = writable }
			byKey[key] = found
		end
		return found.get, found.writable
	end
	local function computedFor(className: string, key: string): ((object: Instance) -> unknown)?
		local getter = computedEntry(className, key)
		return getter
	end
	local function writableComputed(className: string, key: string): boolean
		local _, writable = computedEntry(className, key)
		return writable
	end

	local function defaultOf(className: string, class: Resolved, key: string): unknown
		local declared = class.properties[key]
		local fallback = if key == "Name" then className elseif declared == false then nil else declared
		return if settings.defaultProperty ~= nil then settings.defaultProperty(className, key, fallback) else fallback
	end

	local classDefaults: { [Resolved]: { values: { [string]: unknown }, fresh: { string } } } = {}

	local function defaultsOf(className: string, class: Resolved): { [string]: unknown }
		local cached = classDefaults[class]
		if cached == nil then
			local values: { [string]: unknown } = {}
			local fresh: { string } = {}
			for key in class.properties do
				local value = defaultOf(className, class, key)
				values[key] = value
				if type(value) == "table" and Names.of(value) == nil then
					table.insert(fresh, key)
				end
			end
			cached = { values = values, fresh = fresh }
			classDefaults[class] = cached
		end
		local values = table.clone(cached.values)
		for _, key in cached.fresh do
			values[key] = defaultOf(className, class, key)
		end
		return values
	end

	return {
		specs = specs,
		resolved = resolved,
		defineClass = defineClass,
		resolve = resolve,
		isA = isA,
		computedEntry = computedEntry,
		computedFor = computedFor,
		writableComputed = writableComputed,
		defaultOf = defaultOf,
		defaultsOf = defaultsOf,
	}
end

return create
