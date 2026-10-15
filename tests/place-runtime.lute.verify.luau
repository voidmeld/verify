--!strict

local Roblox = require "../src/roblox"
local Core = require "../src/core"
local PlaceRuntime = require "../src/roblox/place-runtime"
local Scheduler = require "../src/roblox/scheduler"
local luau = require "@std/luau"
local json = require "@std/json"
type Instance = PlaceRuntime.Instance
type Node = PlaceRuntime.State & { parent: Instance?, children: { Instance } }

local function engine(): PlaceRuntime.Engine
	local result = {} :: PlaceRuntime.Engine
	local nodes: { [Instance]: Node } = {}
	local services: { [string]: Instance } = {}
	local function make(kind: string): Instance
		local node: Node = {
			className = kind,
			name = kind,
			parent = nil,
			children = {},
			values = {},
			signals = {},
			propertySignals = {},
		}
		local object = {} :: Instance
		nodes[object] = node
		setmetatable(object, {
			__index = function(_: Instance, key: string): unknown
				if key == "Name" then
					return node.values.Name or node.name
				end
				if key == "ClassName" then
					return node.className
				end
				if key == "Parent" then
					return node.parent
				end
				if key == "GetChildren" then
					return function()
						return table.clone(node.children)
					end
				end
				if key == "GetFullName" then
					return function()
						return node.name
					end
				end
				if key == "FindFirstChild" then
					return function(_: Instance, name: string): Instance?
						for _, child in node.children do
							if child.Name == name then
								return child
							end
						end
						return nil
					end
				end
				return node.values[key]
			end,
			__newindex = function(_: Instance, key: string, value: unknown)
				if key ~= "Parent" then
					node.values[key] = value
					return
				end
				if node.parent then
					local siblings = nodes[node.parent].children
					local index = table.find(siblings, object)
					if index then
						table.remove(siblings, index)
					end
				end
				node.parent = value :: Instance?
				if node.parent then
					table.insert(nodes[node.parent].children, object)
				end
			end,
		})
		return (object :: unknown) :: Instance
	end
	local signals = Roblox.testEnvironment()
	result.signal = signals.newSignal
	result.fire = function(signal: Roblox.Signal, ...: unknown)
		signal:Fire(...)
	end
	result.game = make "DataModel"
	result.newInstance = make
	result.stateOf = function(object: Instance): Node
		return nodes[object]
	end
	result.isInstance = function(object: unknown): boolean
		return nodes[object :: Instance] ~= nil
	end
	result.service = function(name: string): Instance
		if services[name] == nil then
			services[name] = make(name)
			services[name].Parent = result.game
		end
		return services[name]
	end
	result.scheduler = Scheduler.create()
	result.datatypes = Roblox.datatypes
	result.serviceMethods = {}
	result.diagnostics = {}
	result.record = function(kind: string, text: string, source: string)
		table.insert(result.diagnostics, { kind = kind, text = text, source = source })
	end
	local source = function(): string
		return "fixture"
	end
	result.setSourceResolver = function(nextSource: () -> string)
		source = nextSource
	end
	result.currentSource = function(): string
		return source()
	end
	result.typeName = Roblox.typeName
	result.outstandingWaits = function()
		return {}
	end
	result.frames = function(): number
		return 0
	end
	result.blocked = function(): number
		return 0
	end
	result.surface = {
		services = {},
		memberKind = function(): string?
			return nil
		end,
		memberType = function(): string?
			return nil
		end,
	}
	return result
end

return function(suite: Core.Harness)
	suite:case("boots mounted scripts and requires modules without accepting invalid targets", function(check)
		local files = {
			["fixture.json"] = json.serialize {
				tree = {
					ServerScriptService = {
						Main = { ["$path"] = "main.server.luau" },
						Value = { ["$path"] = "value.luau" },
					},
				},
			},
			["main.server.luau"] = 'shared.answer = require("./Value")',
			["value.luau"] = "return 42",
		}
		local host: Roblox.PlaceBootHost<luau.Bytecode> = {
			readFile = function(path: string): string
				return assert(files[path])
			end,
			compile = luau.compile,
			load = function(code: luau.Bytecode, name: string, environment: { [string]: unknown }): () -> unknown
				return luau.load(code, name, environment)
			end,
			encodeJson = function(): string
				error "unused"
			end,
			decodeJson = json.deserialize,
		}
		local report = Roblox.bootPlace({
			projectPath = "fixture.json",
			identity = { universeId = 1, placeId = 2, placeVersion = 3 },
			subject = { name = "Fixture", userId = 4, jobId = "fixture" },
			aliases = {},
			firstViewport = { x = 1, y = 1 },
			finalViewport = { x = 640, y = 480 },
			frames = 1,
			engineProvidedInput = false,
		}, {
			newEngine = engine,
			host = host,
			cache = Roblox.createPlaceCache(host),
			files = {
				exists = function(path: string): boolean
					return files[path] ~= nil
				end,
				fileType = function(): string
					return "file"
				end,
				listDirectory = function()
					return {}
				end,
			},
		})
		check:expect(#report.diagnostics):toBe(0)
		check:expect((report.runtime.globals.shared :: { answer: number }).answer):toBe(42)
		check:expect(report.engine.game.PlaceId):toBe(2)
		check:expect(report.player.Character ~= nil):toBe(true)
		check:expect((pcall(report.runtime.requireInstance, report.player))):toBe(false)
		check:expect((pcall(report.runtime.requireInstance, "@missing/module"))):toBe(false)
	end)
end
