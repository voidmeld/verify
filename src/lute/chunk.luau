--!strict

local luau = require "@lute/luau"

export type Options = {
	name: string?,
	environment: { [string]: unknown }?,
	injectGlobals: boolean?,
}

local function environmentFor(options: Options): { [string]: unknown }
	local supplied = options.environment or {}
	if options.injectGlobals == false then
		return supplied
	end
	local fallback = {
		__index = function(_: unknown, key: string): unknown
			local value = supplied[key]
			if value ~= nil then
				return value
			end
			return (_G)[key]
		end,
	}
	local environment: { [string]: unknown } = {}
	local function attach(value: { [string]: unknown })
		setmetatable(value, fallback)
	end
	attach(environment)
	return environment
end

local compiled: { [string]: luau.Bytecode } = {}

local function bytecode(source: string): luau.Bytecode
	local cached = compiled[source]
	if cached == nil then
		cached = luau.compile(source)
		compiled[source] = cached
	end
	return cached
end

local function load(source: string, options: Options?): (...unknown) -> ...unknown
	local settings: Options = options or {}
	return luau.load(bytecode(source), "@" .. (settings.name or "chunk"), environmentFor(settings))
end

local function check(source: string, name: string?): (boolean, string?)
	local loaded, problem = pcall(luau.load, luau.compile(source), "@" .. (name or "chunk"), {})
	if loaded then
		return true, nil
	end
	return false, tostring(problem)
end

return { load = load, check = check }
