--!strict

local json = require "@std/json"
local luau = require "@std/luau"
local task = require "@std/task"

export type Engine = {
	run: (datamodel: string, code: string) -> string,
	clear: (datamodel: string) -> (),
	attributes: (datamodel: string) -> { [string]: unknown },
}

local function text(value: unknown): string
	if type(value) == "string" then
		return value
	end
	if value == nil then
		return ""
	end
	return json.serialize(value :: json.Value)
end

local function new(globals: { [string]: unknown }): Engine
	local stores: { [string]: { [string]: unknown } } = {}
	local function store(datamodel: string): { [string]: unknown }
		local existing = stores[datamodel]
		if existing == nil then
			existing = {}
			stores[datamodel] = existing
		end
		return existing :: { [string]: unknown }
	end
	local function environment(datamodel: string): { [string]: unknown }
		local attributes = store(datamodel)
		local replicated = {
			GetAttributes = function(): { [string]: unknown }
				return table.clone(attributes)
			end,
			SetAttribute = function(_self: unknown, name: string, value: unknown)
				attributes[name] = value
			end,
			GetAttribute = function(_self: unknown, name: string): unknown
				return attributes[name]
			end,
		}
		local http = {
			JSONEncode = function(_self: unknown, value: unknown): string
				return json.serialize(value :: json.Value)
			end,
		}
		local services: { [string]: unknown } = { ReplicatedStorage = replicated, HttpService = http }
		local env: { [string]: unknown } = {
			game = {
				GetService = function(_self: unknown, name: string): unknown
					return services[name]
				end,
			},
			task = { spawn = task.spawn, wait = task.wait },
			bit32 = bit32,
			string = string,
			math = math,
			table = table,
			type = type,
			tostring = tostring,
			tonumber = tonumber,
			pcall = pcall,
			error = error,
			assert = assert,
			select = select,
			next = next,
			pairs = pairs,
			ipairs = ipairs,
		}
		for name, value in globals do
			env[name] = value
		end
		return env
	end
	return {
		run = function(datamodel: string, code: string): string
			local chunk = luau.load(luau.compile(code), "=engine", environment(datamodel))
			return text(chunk())
		end,
		clear = function(datamodel: string)
			table.clear(store(datamodel))
		end,
		attributes = store,
	}
end

return { new = new }
