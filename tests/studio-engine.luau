--!strict

local Wire = require "../src/lute/wire"

local luau = require "@std/luau"
local task = require "@std/task"
local Environment = require "../src/roblox/environment"

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
	return Wire.encode(value)
end

local function new(globals: { [string]: unknown }): Engine
	local stores: { [string]: Environment.Environment } = {}
	local function store(datamodel: string): Environment.Environment
		local existing = stores[datamodel]
		if existing == nil then
			existing = Environment.create {
				limits = { attributeStringLength = 50 },
				classes = { StringValue = { super = "Instance", properties = { Value = "" } } },
			}
			stores[datamodel] = existing
		end
		return existing
	end
	local function environment(datamodel: string): { [string]: unknown }
		local instances = store(datamodel)
		local replicated = instances.root
		local http = {
			JSONEncode = function(_self: unknown, value: unknown): string
				return Wire.encode(value)
			end,
		}
		local services: { [string]: unknown } = { ReplicatedStorage = replicated, HttpService = http }
		local env: { [string]: unknown } = {
			Instance = { new = instances.createInstance },
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
			stores[datamodel] = nil
		end,
		attributes = function(datamodel: string): { [string]: unknown }
			return store(datamodel).root:GetAttributes()
		end,
	}
end

return { new = new }
