--!strict

export type Fields = { [unknown]: unknown }
export type Behavior = {
	name: string,
	label: string,
	quoted: boolean,
	fields: { [string]: unknown },
	meta: { [string]: unknown },
}

local proxyMetatable = getmetatable
local function weak<K, V>(values: { [K]: V })
	setmetatable(values, { __mode = "kv" })
end

local registered: { [unknown]: string } = {}
weak(registered)
local behaviors: { [unknown]: Behavior } = {}
local storage: { [unknown]: Fields } = {}
weak(behaviors)
weak(storage)

local function behaviorOf(value: unknown): Behavior?
	if type(value) ~= "userdata" then
		return nil
	end
	return behaviors[value]
end

local function invalid(member: unknown, owner: string): never
	error(("%s is not a valid member of %s"):format(tostring(member), owner), 3)
end

local function readOnly(member: unknown, owner: string): never
	error(("%s member of %s is read-only and cannot be assigned to"):format(tostring(member), owner), 3)
end

local function kindOf(value: unknown): string
	local found = behaviorOf(value)
	return if found ~= nil then found.name else registered[value] or typeof(value)
end

local function arithmetic(operation: string, left: unknown, right: unknown): never
	local a, b = kindOf(left), kindOf(right)
	if a == b then
		error(("attempt to perform arithmetic (%s) on %s"):format(operation, a), 3)
	end
	error(("attempt to perform arithmetic (%s) on %s and %s"):format(operation, a, b), 3)
end

local function arithmeticDefault(operation: string): (unknown, unknown) -> never
	return function(left: unknown, right: unknown): never
		return arithmetic(operation, left, right)
	end
end

local function compareDefault(operator: string): (unknown, unknown) -> never
	return function(left: unknown, right: unknown): never
		error(("attempt to compare %s %s %s"):format(kindOf(left), operator, kindOf(right)), 2)
	end
end

export type BehaviorOptions = { owner: string?, quoted: boolean? }

local function behavior(name: string, options: BehaviorOptions?): Behavior
	local settings: BehaviorOptions = options or {}
	local label = settings.owner or name
	local quoted = settings.quoted == true
	return {
		name = name,
		label = label,
		quoted = quoted,
		fields = {
			__index = function(_: unknown, key: unknown): unknown
				return invalid(if quoted then "'" .. tostring(key) .. "'" else key, label)
			end,
		},
		meta = {
			__newindex = function(_: unknown, key: unknown, _value: unknown)
				readOnly(key, label)
			end,
			__add = arithmeticDefault "add",
			__sub = arithmeticDefault "sub",
			__mul = arithmeticDefault "mul",
			__div = arithmeticDefault "div",
			__idiv = arithmeticDefault "idiv",
			__mod = arithmeticDefault "mod",
			__pow = arithmeticDefault "pow",
			__unm = function(value: unknown): never
				return arithmetic("unm", value, value)
			end,
			__lt = compareDefault "<",
			__le = compareDefault "<=",
			__concat = function(left: unknown, right: unknown): never
				error(("attempt to concatenate %s with %s"):format(kindOf(left), kindOf(right)), 2)
			end,
			__len = function(value: unknown): never
				error(("attempt to get length of a %s value"):format(kindOf(value)), 2)
			end,
			__call = function(value: unknown): never
				error(("attempt to call a %s value"):format(kindOf(value)), 2)
			end,
		},
	}
end

local function missing(kind: Behavior, key: unknown): never
	error(
		("%s is not a valid member of %s"):format(
			if kind.quoted then "'" .. tostring(key) .. "'" else tostring(key),
			kind.label
		),
		3
	)
end

local function make(kind: Behavior, fields: Fields)
	local proxy = newproxy(true)
	local metatable: Fields = proxyMetatable(proxy)
	for key, method in kind.meta do
		metatable[key] = method
	end
	behaviors[proxy] = kind
	storage[proxy] = fields
	metatable.__index = setmetatable(fields, kind.fields)
	return proxy
end

local function fields(value: unknown): Fields
	return storage[value]
end

local function of(value: unknown): string?
	local found = behaviorOf(value)
	return if found ~= nil then found.name else nil
end

local function kind(value: unknown): string
	return kindOf(value)
end

local function is(value: unknown, expected: Behavior): boolean
	return behaviorOf(value) == expected
end

local function argument(position: number, expected: string, value: unknown): never
	error(("invalid argument #%d (%s expected, got %s)"):format(position, expected, kind(value)), 3)
end

return {
	weak = weak,
	registered = function(value: unknown): string?
		return registered[value]
	end,
	register = function(value: unknown, name: string)
		registered[value] = name
	end,
	behavior = behavior,
	make = make,
	fields = fields,
	of = of,
	kind = kind,
	is = is,
	invalid = invalid,
	missing = missing,
	readOnly = readOnly,
	argument = argument,
	arithmetic = arithmetic,
}
