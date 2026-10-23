--!strict

local Roblox = require "../src/roblox"
local Core = require "../src/core"
local PlaceRuntime = require "../src/roblox/place-runtime"
local Environment = require "../src/roblox/environment"
local luau = require "@std/luau"
local json = require "@std/json"
local Lute = require "../src/lute"
type Instance = PlaceRuntime.Instance
local function engine(): Roblox.PlaceBootEngine
	local environment = Roblox.testEnvironment { undeclaredWrites = true, undeclaredReads = "nil" }
	local declared: { [string]: boolean } = { Animator = true, Animation = true, AnimationTrack = true }
	local events = {
		RunService = { "PreRender", "RenderStepped", "Heartbeat", "Stepped", "PreSimulation", "PostSimulation" },
		Players = { "PlayerAdded" },
		Player = { "CharacterAdded" },
	}
	local function make(kind: string): Instance
		if not declared[kind] then
			if Environment.BASIC_CLASSES[kind] == nil then
				environment.defineClass(kind, { super = "Instance", events = events[kind] })
			end
			declared[kind] = true
		end
		return (environment.createInstance(kind) :: unknown) :: Instance
	end
	local game = make "DataModel"
	local services: { [string]: Instance } = {}
	local diagnostics: { PlaceRuntime.Diagnostic } = {}
	local source = function(): string
		return "fixture"
	end
	return {
		environment = environment,
		game = game,
		newInstance = make,
		isInstance = Roblox.isInstance,
		service = function(name: string): Instance
			if services[name] == nil then
				services[name] = make(name)
				services[name].Parent = game
			end
			return services[name]
		end,
		datatypes = Roblox.datatypes,
		diagnostics = diagnostics,
		record = function(kind: string, text: string, origin: string)
			table.insert(diagnostics, { kind = kind, text = text, source = origin })
		end,
		setSourceResolver = function(nextSource: () -> string)
			source = nextSource
		end,
		currentSource = function(): string
			return source()
		end,
		typeName = Roblox.typeName,
		surface = {
			services = {},
			memberKind = function(): string?
				return nil
			end,
			memberType = function(): string?
				return nil
			end,
		},
	}
end
local function sourceFixture(
	sources: { [string]: string },
	methodDoubles: { string }?,
	options: {
		engine: PlaceRuntime.Engine?,
		client: PlaceRuntime.Client?,
		beforeRender: (() -> ())?,
	}?
)
	local settings: {
		engine: PlaceRuntime.Engine?,
		client: PlaceRuntime.Client?,
		beforeRender: (() -> ())?,
	} = options
		or {}
	local binding = settings.engine or engine()
	local compilations = 0
	local host: Roblox.PlaceBootHost<luau.Bytecode> = {
		readFile = function(path: string): string
			return assert(sources[path], path)
		end,
		compile = function(source: string): luau.Bytecode
			compilations += 1
			return luau.compile(source)
		end,
		load = function(code: luau.Bytecode, name: string, globals: { [string]: unknown }): () -> unknown
			return luau.load(code, name, globals)
		end,
		encodeJson = function(value: unknown): string
			return json.serialize(value :: json.Value)
		end,
		decodeJson = json.deserialize,
	}
	local mounted: PlaceRuntime.Mounted = { root = binding.game, scripts = {}, sources = {} }
	return {
		compilations = function(): number
			return compilations
		end,
		engine = binding,
		host = host,
		mounted = mounted,
		runtime = Roblox.createPlaceRuntime(binding, mounted, {
			aliases = { fixture = "fixture" },
			cache = Roblox.createPlaceCache(host),
			host = host,
			methodDoubles = methodDoubles or { "DataModel", "RunService", "HttpService" },
			client = settings.client,
			beforeRender = settings.beforeRender,
		}),
		module = function(name: string, path: string, parent: Instance?): Instance
			local object = binding.newInstance "ModuleScript"
			object.Name = name
			object.Parent = parent or binding.game
			mounted.sources[object] = path
			return object
		end,
	}
end

return function(suite: Core.Harness)
	suite:case("explicit humanoid transitions require a parented model and scheduled work", function(check)
		local binding = Lute.fixture.bridge().placeEngine()
		local fixture = sourceFixture({
			["state.luau"] = [[
local rig = Instance.new("Model")
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = rig
local humanoid = Instance.new("Humanoid")
humanoid.Parent = rig
local changes = {}
humanoid.StateChanged:Connect(function(old, new) table.insert(changes, {old.Name, new.Name}) end)
return {
    state = function() return humanoid:GetState().Name end,
    parent = function() rig.Parent = workspace end,
    change = function() humanoid:ChangeState(Enum.HumanoidStateType.Physics) end,
    detach = function() rig.Parent = nil end,
    changes = changes,
}
]],
		}, { "DataModel", "Humanoid", "RunService" }, { engine = binding })
		local subject = fixture.runtime.requireInstance(fixture.module("State", "state.luau")) :: {
			state: () -> string,
			parent: () -> (),
			change: () -> (),
			detach: () -> (),
			changes: { { string } },
		}
		check:expect(subject.state()):toBe "None"
		subject.change()
		fixture.runtime.step(0.1)
		check:expect(subject.state()):toBe "None"
		subject.parent()
		check:expect(subject.state()):toBe "Running"
		subject.change()
		check:expect(subject.state()):toBe "Running"
		fixture.runtime.step(0.1)
		check:expect(subject.state()):toBe "Physics"
		check:expect(subject.changes):toEqual { { "Running", "Physics" } }
		subject.detach()
		check:expect(subject.state()):toBe "None"
		check:expect(binding.environment.scheduler.failures):toEqual {}
	end)

	suite:case("loading-screen removal allows asynchronous arrival logic to continue", function(check)
		local binding = Lute.fixture.bridge().placeEngine()
		local fixture = sourceFixture({
			["arrival.luau"] = [[
local ready = false
task.spawn(function()
    game:GetService("ReplicatedFirst"):RemoveDefaultLoadingScreen()
    ready = true
end)
return function() return ready end
]],
		}, { "DataModel", "ReplicatedFirst" }, { engine = binding })
		local ready = fixture.runtime.requireInstance(fixture.module("Arrival", "arrival.luau")) :: () -> boolean
		binding.environment.scheduler.drain(64)
		check:expect(binding.environment.scheduler.failures):toEqual {}
		check:expect(ready()):toBe(true)
	end)

	suite:case("instrumented modules execute without changing host debug functions", function(check)
		local before = table.clone(debug)
		local fixture = sourceFixture {
			["instrumented.luau"] = [[
debug.setmemorycategory("fixture")
debug.profilebegin("work")
local result = 6 * 7
debug.profileend()
return {result, type(debug.traceback), (pcall(debug.profilebegin, {}))}
]],
		}
		local result = fixture.runtime.requireInstance(fixture.module("Instrumented", "instrumented.luau"))
		local expected: { unknown } = { 42, "function", false }
		check:expect(result):toEqual(expected)
		check:expect(debug):toEqual(before)
	end)

	suite:case("place defaults preserve configured service behavior and release their own overrides", function(check)
		local binding = Lute.fixture.bridge().placeEngine()
		local refuse = false
		binding.environment.fake("DataStoreService.GetDataStore", function()
			assert(not refuse, "configured store unavailable")
			return "configured store"
		end)
		local run = binding.service "RunService"
		local release = binding.environment.fakeOn(run, "IsStudio", function()
			return true
		end)
		local fixture = sourceFixture({
			["services.luau"] = "return function() return {game:GetService('DataStoreService'):GetDataStore('isolated'), game:GetService('RunService'):IsStudio(), workspace:GetServerTimeNow()} end",
		}, { "DataModel", "DataStoreService", "RunService", "Workspace" }, { engine = binding })
		local read = fixture.runtime.requireInstance(fixture.module("Services", "services.luau")) :: () -> unknown
		local expected: { unknown } = { "configured store", true, 0 }
		check:expect(read()):toEqual(expected)
		refuse = true
		local ok, failure = pcall(read)
		check:expect(ok):toBe(false)
		check:expect(tostring(failure)):toContain "configured store unavailable"
		refuse = false
		for _, close in fixture.runtime.closeHandlers do
			close()
		end
		check:expect((run.IsStudio :: (Instance) -> boolean)(run)):toBe(true)
		local store = binding.service "DataStoreService"
		check:expect((store.GetDataStore :: (Instance, string) -> string)(store, "isolated")):toBe "configured store"
		check
			:expect((pcall(function()
				return binding.service("Workspace").GetServerTimeNow
			end)))
			:toBe(false)
		release()
	end)

	suite:case("place services follow virtual time and input while retaining content URIs", function(check)
		local binding = Lute.fixture.bridge().placeEngine()
		local fixture = sourceFixture({
			["clock.luau"] = "return function() return workspace:GetServerTimeNow() end",
			["input.luau"] = "return function() return game:GetService('UserInputService'):GetLastInputType() end",
			["mesh.luau"] = "return game:GetService('AssetService'):CreateMeshPartAsync(Content.fromUri('rbxassetid://123')).MeshId",
			["empty.luau"] = "return game:GetService('AssetService'):CreateMeshPartAsync(Content.none)",
		}, { "DataModel", "RunService", "Workspace", "UserInputService", "AssetService" }, { engine = binding })
		local clock = fixture.runtime.requireInstance(fixture.module("Clock", "clock.luau")) :: () -> number
		local input = fixture.runtime.requireInstance(fixture.module("Input", "input.luau")) :: () -> unknown
		local start = clock()
		fixture.runtime.step(0.25)
		check:expect(clock() - start):toBe(0.25)
		check:expect(input()):toBe(binding.datatypes.Enum.UserInputType.None)
		local service = binding.service "UserInputService"
		local event = binding.newInstance("InputObject", true)
		binding.environment.poke(event, "UserInputType", binding.datatypes.Enum.UserInputType.Touch)
		binding.environment.fire(service, "InputBegan", event, false)
		binding.environment.scheduler.drain(64)
		check:expect(input()):toBe(binding.datatypes.Enum.UserInputType.Touch)
		check:expect(binding.environment.connectionsOfInstance(service)):toBe(3)
		check:expect(fixture.runtime.requireInstance(fixture.module("Mesh", "mesh.luau"))):toBe "rbxassetid://123"
		check:expect((pcall(fixture.runtime.requireInstance, fixture.module("Empty", "empty.luau")))):toBe(false)
		for _, close in fixture.runtime.closeHandlers do
			close()
		end
		check:expect(binding.environment.connectionsOfInstance(service)):toBe(0)
	end)

	suite:case("project paths resolve beside the project and retain absolute source paths", function(check)
		for _, target in { "../modules/value.luau", "/modules/value.luau", "C:/modules/value.luau" } do
			local expected = if target == "../modules/value.luau" then "modules/value.luau" else target
			local fixture = sourceFixture {
				["config/fixture.json"] = json.serialize {
					tree = { ReplicatedStorage = { Value = { ["$path"] = target } } },
				},
				[expected] = "return 42",
			}
			local mounted = Roblox.buildPlaceTree(fixture.engine, "config/fixture.json", {
				cache = Roblox.createPlaceCache(fixture.host),
				host = fixture.host,
				files = {
					exists = function(path: string): boolean
						return path == expected
					end,
					fileType = function(): string
						return "file"
					end,
					listDirectory = function()
						return {}
					end,
				},
			})
			local value = assert(fixture.engine.service("ReplicatedStorage"):FindFirstChild "Value")
			check:expect(value.ClassName):toBe "ModuleScript"
			check:expect(mounted.sources[value]):toBe(expected)
		end
	end)
	suite:case("bundled place clients run requested source with bounded frame stepping", function(check)
		local bridge = Lute.fixture.bridge(nil, { handlerErrors = "raise" })
		local order: { string } = {}
		local fixture = sourceFixture({
			["fixture/client.luau"] = [[
local players = game:GetService("Players")
local player = players.LocalPlayer
assert(player.Name == "Fixture" and player.UserId == 7)
assert(player.PlayerGui.Parent == player)
assert(workspace.CurrentCamera.ViewportSize == Vector2.new(640, 480))
local run = game:GetService("RunService")
run.RenderStepped:Wait()
return "client-ready"
]],
		}, { "DataModel", "RunService", "Players", "HttpService" }, {
			engine = bridge.placeEngine(),
			client = { name = "Fixture", userId = 7, viewport = { x = 640, y = 480 } },
			beforeRender = function()
				table.insert(order, "layout")
			end,
		})
		local module = fixture.module("Client", "fixture/client.luau")
		local result: unknown = nil
		local env = bridge.environment
		local render = fixture.engine.service("RunService").RenderStepped :: Environment.Signal
		render:Connect(function()
			table.insert(order, "render")
		end)
		env.scheduler.spawnTagged({ context = "client", source = "fixture/client.luau" }, function()
			result = fixture.runtime.requireInstance(module)
		end)
		check:expect(result):toBe(nil)
		fixture.runtime.step(1 / 60)
		check:expect(result):toBe "client-ready"
		check:expect(order):toEqual { "layout", "render" }
		check:expect(#env.errors):toBe(0)
		check:expect(#fixture.engine.diagnostics):toBe(0)
		for _, close in fixture.runtime.closeHandlers do
			close()
		end
		bridge.close()
	end)
	suite:case("place frame readers fail closed before publishing render events", function(check)
		local frames = 0
		local fixture = sourceFixture({}, nil, {
			beforeRender = function()
				error "layout reader failure"
			end,
		})
		local render = fixture.engine.service("RunService").RenderStepped :: Environment.Signal
		render:Connect(function()
			frames += 1
		end)
		local ok, failure = pcall(function(): unknown
			fixture.runtime.step(1 / 60)
			return nil
		end)
		check:expect(ok):toBe(false)
		check:expect(tostring(failure)):toContain "layout reader failure"
		check:expect(frames):toBe(0)
		for _, duration in { -1, math.huge, math.nan } do
			check:expect((pcall(fixture.runtime.step, duration))):toBe(false)
		end
	end)
	suite:case(
		"modeled preload accepts an empty request and refuses unresolved assets without callbacks",
		function(check)
			local fixture = sourceFixture({}, { "DataModel", "ContentProvider" })
			local service = fixture.engine.service "ContentProvider"
			local preload = service.PreloadAsync :: (Instance, { unknown }, (string, unknown) -> ()) -> ()
			local calls = 0
			local function callback(_asset: string, _status: unknown)
				calls += 1
			end
			preload(service, {}, callback)
			check:expect(calls):toBe(0)
			local requests: { { unknown } } = { { "rbxassetid://1" }, { fixture.engine.newInstance "ImageLabel" } }
			for _, assets in requests do
				local ok, failure = pcall(function()
					preload(service, assets, callback)
					return "returned without resolving assets"
				end)
				check:expect(ok):toBe(false)
				check:expect(tostring(failure)):toContain "unsupported_place_asset: ContentProvider.PreloadAsync"
				check:expect(calls):toBe(0)
			end
		end
	)
	suite:case(
		"CollectionService shares Instance tags and matches native DataModel entry and pending removal",
		function(check)
			local fixture = sourceFixture({}, { "DataModel", "RunService", "HttpService", "CollectionService" })
			local env, game = fixture.engine.environment, fixture.engine.game
			local service = fixture.engine.service "CollectionService"
			local get = service.GetTagged :: (Instance, string) -> { Instance }
			local added = (service.GetInstanceAddedSignal :: (Instance, string) -> Environment.Signal<Instance>)(
				service,
				"Hot"
			)
			local removed = (service.GetInstanceRemovedSignal :: (Instance, string) -> Environment.Signal<Instance>)(
				service,
				"Hot"
			)
			local events: { string } = {}
			local function subscribe(signal: Environment.Signal<Instance>, name: string)
				signal:Connect(function(object)
					table.insert(
						events,
						name
							.. ":"
							.. tostring(object:HasTag "Hot")
							.. ":"
							.. tostring(object:IsDescendantOf(game))
							.. ":"
							.. #get(service, "Hot")
					)
				end)
			end
			subscribe(added, "added")
			subscribe(removed, "removed")
			local object = fixture.engine.newInstance "Folder"
			object:AddTag "Hot"
			check:expect(get(service, "Hot")):toEqual {}
			object.Parent = game
			object:AddTag "Hot"
			local addTag = (service.AddTag :: unknown) :: (Instance, Instance, string) -> ()
			local removeTag = (service.RemoveTag :: unknown) :: (Instance, Instance, string) -> ()
			removeTag(service, object, "Hot")
			addTag(service, object, "Hot")
			addTag(service, object, "Hot")
			object.Parent = nil
			object.Parent = game
			object:RemoveTag "Hot"
			object:AddTag "Hot"
			object:Destroy()
			check:expect(events):toEqual {
				"added:true:true:1",
				"removed:false:true:0",
				"added:true:true:1",
				"removed:true:true:0",
				"added:true:true:1",
				"removed:false:true:0",
				"added:true:true:1",
				"removed:true:true:0",
			}
			check:expect(object:HasTag "Hot"):toBe(true)
			check:expect(get(service, "Hot")):toEqual {}
			table.clear(events)
			local parent = fixture.engine.newInstance "Folder"
			local child = fixture.engine.newInstance "Folder"
			parent:AddTag "Hot"
			child:AddTag "Hot"
			child.Parent = parent
			parent.Parent = game
			check:expect(events):toEqual { "added:true:true:2", "added:true:true:2" }
			table.clear(events)
			local container = fixture.engine.newInstance "Folder"
			container.Parent = game
			parent.Parent = container
			check:expect(events):toEqual {}
			parent.Parent = nil
			check:expect(events):toEqual { "removed:true:true:1", "removed:true:true:0" }
			game:AddTag "Hot"
			check:expect(get(service, "Hot")):toEqual { game }
			game:RemoveTag "Hot"
			for _, close in fixture.runtime.closeHandlers do
				close()
			end
			check:expect(env.liveConnections()):toBe(0)
		end
	)
	suite:case(
		"ModuleScript type and typeof preserve native identities without classifying spoofed tables",
		function(check)
			local fixture = sourceFixture {
				["fixture/Kinds.luau"] = "return {type(script),typeof(script),type(shared.object),typeof(shared.object),type(shared.signal),typeof(shared.signal),type(shared.connection),typeof(shared.connection),type({__state={class={instance=true}}}),typeof({__state={class={instance=true}}})}",
			}
			local env = fixture.engine.environment
			env.defineClass("VirtualInput", { super = "Object", creatable = false })
			local object = env.createEngineObject "VirtualInput"
			local signal = env.newSignal()
			local connection = signal:Connect(function() end)
			local shared = fixture.runtime.globals.shared :: { [string]: unknown }
			shared.object, shared.signal, shared.connection = object, signal, connection
			local module = fixture.module("Kinds", "fixture/Kinds.luau")
			check:expect(fixture.runtime.requireInstance(module)):toEqual {
				"userdata",
				"Instance",
				"userdata",
				"Object",
				"userdata",
				"RBXScriptSignal",
				"userdata",
				"RBXScriptConnection",
				"table",
				"table",
			}
			connection:Disconnect()
			env.releaseObject(object)
		end
	)
	suite:case("ModuleScript caches by instance identity while sharing source bytecode", function(check)
		local fixture = sourceFixture {
			["value.luau"] = "shared.executions = (shared.executions or 0) + 1; return { execution = shared.executions }",
		}
		local first = fixture.module("First", "value.luau")
		local second = fixture.module("Second", "value.luau")
		local firstValue = fixture.runtime.requireInstance(first)
		check:expect(fixture.runtime.requireInstance(first) == firstValue):toBe(true)
		check:expect(firstValue == fixture.runtime.requireInstance(second)):toBe(false)
		check:expect((fixture.runtime.globals.shared :: { executions: number }).executions):toBe(2)
		check:expect(fixture.compilations()):toBe(1)
	end)

	suite:case("ModuleScript resolves init children sibling paths and parent paths on the mounted tree", function(check)
		local fixture = sourceFixture {
			["package/init.luau"] = 'return { relative = require("./Shared"), own = require("@self/Value") }',
			["package/value.luau"] = "return 42",
			["package/main.luau"] = 'return { sibling = require("./Value"), parent = require("../Shared") }',
			["shared.luau"] = "return 7",
		}
		local package = fixture.module("Package", "package/init.luau")
		fixture.module("Value", "package/value.luau", package)
		local main = fixture.module("Main", "package/main.luau", package)
		fixture.module("Shared", "shared.luau")
		local packageValue = fixture.runtime.requireInstance(package) :: { relative: number, own: number }
		check:expect(packageValue.relative):toBe(7)
		check:expect(packageValue.own):toBe(42)
		local mainValue = fixture.runtime.requireInstance(main) :: { sibling: number, parent: number }
		check:expect(mainValue.sibling):toBe(42)
		check:expect(mainValue.parent):toBe(7)
	end)

	suite:case("ModuleScript repeats runtime and compile errors without leaving a loading cache entry", function(check)
		local fixture = sourceFixture {
			["failure.luau"] = 'error("module fixture failure")',
			["syntax.luau"] = "return (",
		}
		for _, name in { "failure", "syntax" } do
			local object = fixture.module(name, name .. ".luau")
			local errors: { string } = {}
			for _ = 1, 2 do
				local ok, failure = pcall(fixture.runtime.requireInstance, object)
				check:expect(ok):toBe(false)
				table.insert(errors, tostring(failure))
			end
			check:expect(errors[1]):toBe(errors[2])
			check:expect(errors[1]):toContain "Requested module experienced an error while loading"
		end
		check:expect(#fixture.engine.diagnostics):toBe(2)
		check:expect(fixture.engine.diagnostics[1].source):toBe "failure.luau"
		check:expect(fixture.engine.diagnostics[1].text):toContain "module fixture failure"
		check:expect(fixture.engine.diagnostics[2].source):toBe "syntax.luau"
		local missing = fixture.module("Missing", "absent.luau")
		fixture.mounted.sources[missing] = nil
		check:expect((pcall(fixture.runtime.requireInstance, missing))):toBe(false)
		check:expect((pcall(fixture.runtime.requireInstance, fixture.engine.game))):toBe(false)
	end)

	suite:case(
		"place runtime installs only selected method doubles on existing and new service instances",
		function(check)
			local fixture = sourceFixture {}
			local get = fixture.engine.game.GetService :: (Instance, string) -> Instance
			check:expect(get(fixture.engine.game, "RunService") == fixture.engine.service "RunService"):toBe(true)
			check:expect(fixture.engine.service("ContentProvider").PreloadAsync):toBe(nil)
			for _, close in fixture.runtime.closeHandlers do
				close()
			end
			check:expect(fixture.engine.service("HttpService").JSONEncode):toBe(nil)
		end
	)

	suite:case("boots mounted scripts and requires modules without accepting invalid targets", function(check)
		local files = {
			["fixture.json"] = json.serialize {
				tree = {
					Lighting = {
						["$properties"] = { Ambient = { Color3 = { 0.2, 0.3, 0.4 } }, LightingStyle = "Realistic" },
					},
					Workspace = {
						Stand = {
							["$className"] = "Part",
							["$properties"] = {
								Size = { Vector3 = { 4, 2, 6 } },
								Shape = { Enum = 1 },
								CFrame = {
									CFrame = {
										position = { 1, 2, 3 },
										orientation = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
									},
								},
							},
						},
					},
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
			newEngine = function()
				return Lute.fixture.bridge().placeEngine()
			end,
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
		local types = report.engine.datatypes
		check:expect(report.engine.service("Lighting").Ambient):toBe(types.Color3.new(0.2, 0.3, 0.4))
		check:expect(report.engine.service("Lighting").LightingStyle):toBe(types.Enum.LightingStyle.Realistic)
		check:expect(report.engine.game.RunService):toBe(report.engine.service "RunService")
		local stand = assert(report.engine.service("Workspace"):FindFirstChild "Stand")
		check:expect(stand.Size):toBe(types.Vector3.new(4, 2, 6))
		check:expect(stand.Shape):toBe(types.Enum.PartType.Block)
		check:expect(stand.CFrame):toBe(types.CFrame.new(1, 2, 3))
		check:expect(report.player.Character ~= nil):toBe(true)
		check:expect((pcall(report.runtime.requireInstance, report.player))):toBe(false)
		check:expect((pcall(report.runtime.requireInstance, "@missing/module"))):toBe(false)
		files["fixture.json"] = json.serialize {
			tree = {
				Lighting = { ["$properties"] = { Ambient = { Color3 = { 0.2, "invalid", 0.4 } :: { unknown } } } },
			},
		}
		check
			:expect((pcall(Roblox.buildPlaceTree, report.engine, "fixture.json", {
				host = host,
				cache = Roblox.createPlaceCache(host),
				files = {
					exists = function()
						return false
					end,
					fileType = function()
						return "file"
					end,
					listDirectory = function()
						return {}
					end,
				},
			})))
			:toBe(false)
	end)
end
