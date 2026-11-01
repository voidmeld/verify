--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local PlaceRuntime = require "../src/roblox/place-runtime"
local Environment = require "../src/roblox/environment"
local VM = require "../src/roblox/value"
local luau = require "@std/luau"
local json = require "@std/json"
local Lute = require "../src/lute"
type Instance = PlaceRuntime.Instance

local field = Environment.vm.read

local function method(value: VM.Value): (...unknown) -> ...VM.Value
	return function(...: unknown): ...VM.Value
		return Environment.invoke(value, ...)
	end
end

local function record(value: unknown)
	assert(type(value) == "table")
	return value
end

local function number(value: unknown): number
	assert(type(value) == "number")
	return value
end

local function engine(): Roblox.PlaceBootEngine
	local options: Environment.Options = { undeclaredWrites = true, undeclaredReads = "nil" }
	local environment = Roblox.testEnvironment(options)
	local declared: { [string]: boolean } = { Animator = true, Animation = true, AnimationTrack = true }
	local events: { [string]: { string } } = {
		RunService = { "PreRender", "RenderStepped", "Heartbeat", "Stepped", "PreSimulation", "PostSimulation" },
		Players = { "PlayerAdded" },
		Player = { "CharacterAdded" },
	}
	local function make(kind: string): Instance
		if not declared[kind] then
			if Environment.BASIC_CLASSES[kind] == nil then
				local spec: Environment.ClassSpec = { super = "Instance", events = events[kind] }
				environment.defineClass(kind, spec)
			end
			declared[kind] = true
		end
		return assert((environment.createInstance(kind)))
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
	local host: PlaceRuntime.Host<luau.Bytecode> = {
		readFile = function(path: string): string
			return assert(sources[path], path)
		end,
		compile = function(source: string): luau.Bytecode
			compilations += 1
			return luau.compile(source)
		end,
		load = function(code: luau.Bytecode, name: string, globals: { [string]: unknown }): () -> VM.Value
			return luau.load(code, name, globals)
		end,
		encodeJson = function(value: unknown): string
			return Lute.encode(value)
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

it("place tweens share progressive interpolation and easing with the engine", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["tween.luau"] = [[
local service = game:GetService("TweenService")
local frame = Instance.new("Frame")
local tween = service:Create(frame, TweenInfo.new(1, Enum.EasingStyle.Linear), {Position = UDim2.fromOffset(100, 200)})
tween:Play()
return {
    position = function() return frame.Position.X.Offset end,
    ease = service:GetValue(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
    cancel = function() tween:Cancel() end,
    dispose = function() tween:Destroy() frame:Destroy() end,
}
]],
	}, { "DataModel", "RunService", "TweenService" }, { engine = binding })
	local loaded, result = pcall(fixture.runtime.requireInstance, fixture.module("Tween", "tween.luau"))
	assert(loaded, Lute.encode(binding.diagnostics))
	local resultRecord = result
	local position, cancel, dispose =
		method(field(resultRecord, "position")),
		method(field(resultRecord, "cancel")),
		method(field(resultRecord, "dispose"))
	expect(position()):toBe(0)
	expect(field(resultRecord, "ease")):toBe(0.875)
	fixture.runtime.step(0.5)
	expect(position()):toBe(50)
	cancel()
	fixture.runtime.step(0.5)
	expect(position()):toBe(50)
	dispose()
	expect(binding.environment.scheduler.failures):toEqual {}
end)

it("MemoryStore handles preserve names without simulating backend operations", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["handles.luau"] = [[
local service = game:GetService("MemoryStoreService")
local first = service:GetHashMap("first")
assert(first:IsA("MemoryStoreHashMap"))
assert(first.Name == "Instance" and first.Parent == service)
assert(service:GetHashMap("first") == first)
assert(service:GetHashMap("second") ~= first)
assert(service:GetHashMap(""):IsA("MemoryStoreHashMap"))
assert(service:GetHashMap(1) == service:GetHashMap("1"))
local ok, failure = pcall(function() return first:GetAsync("key") end)
assert(not ok and string.find(tostring(failure), "unsupported_method: MemoryStoreHashMap.GetAsync", 1, true))
return true
]],
	}, { "DataModel", "MemoryStoreService" }, { engine = binding })
	binding.environment.poke(binding.game, "GameId", 1)
	expect(fixture.runtime.requireInstance(fixture.module("Handles", "handles.luau"))):toBe(true)
end)
it("MemoryStore handle acquisition refuses an unpublished place", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["unpublished.luau"] = [[
local ok, failure = pcall(function() return game:GetService("MemoryStoreService"):GetHashMap("first") end)
assert(not ok)
return tostring(failure)
]],
	}, { "DataModel", "MemoryStoreService" }, { engine = binding })
	local failure = fixture.runtime.requireInstance(fixture.module("Unpublished", "unpublished.luau"))
	expect(failure):toContain "You must publish this place"
end)
it("explicit humanoid transitions require a parented model and scheduled work", function()
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
	local subject = fixture.runtime.requireInstance(fixture.module("State", "state.luau"))
	expect(method(field(subject, "state"))()):toBe "None"
	method(field(subject, "change"))()
	fixture.runtime.step(0.1)
	expect(method(field(subject, "state"))()):toBe "None"
	method(field(subject, "parent"))()
	expect(method(field(subject, "state"))()):toBe "Running"
	method(field(subject, "change"))()
	expect(method(field(subject, "state"))()):toBe "Running"
	fixture.runtime.step(0.1)
	expect(method(field(subject, "state"))()):toBe "Physics"
	expect(field(subject, "changes")):toEqual { { "Running", "Physics" } }
	method(field(subject, "detach"))()
	expect(method(field(subject, "state"))()):toBe "None"
	expect(binding.environment.scheduler.failures):toEqual {}
end)

it("humanoid state flags notify on repeated writes but are not cloned", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["flags.luau"] = [[
local h = Instance.new("Humanoid")
local state = Enum.HumanoidStateType.Ragdoll
local events = {}
h.StateEnabledChanged:Connect(function(state, enabled) table.insert(events, {state.Name, enabled}) end)
local initial = h:GetStateEnabled(state)
h:SetStateEnabled(state, false)
h:SetStateEnabled(state, false)
h:SetStateEnabled(Enum.HumanoidStateType.None, false)
return {initial=initial, disabled=h:GetStateEnabled(state), copy=h:Clone():GetStateEnabled(state), none=h:GetStateEnabled(Enum.HumanoidStateType.None), events=events}
]],
	}, { "DataModel", "Humanoid", "RunService" }, { engine = binding })
	local actual = fixture.runtime.requireInstance(fixture.module("Flags", "flags.luau"))
	local events: { { unknown } } = { { "Ragdoll", false }, { "Ragdoll", false } }
	expect(actual):toEqual {
		initial = true,
		disabled = false,
		copy = true,
		none = true,
		events = events,
	}
end)
it("loading-screen removal allows asynchronous arrival logic to continue", function()
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
	local ready = method(fixture.runtime.requireInstance(fixture.module("Arrival", "arrival.luau")))
	binding.environment.scheduler.drain(64)
	expect(binding.environment.scheduler.failures):toEqual {}
	expect(ready()):toBe(true)
end)

it("instrumented modules execute without changing host debug functions", function()
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
	expect(result):toEqual(expected)
	expect(debug):toEqual(before)
end)

it("place defaults preserve configured service behavior and release their own overrides", function()
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
	local read = method(fixture.runtime.requireInstance(fixture.module("Services", "services.luau")))
	local expected: { unknown } = { "configured store", true, 0 }
	expect(read()):toEqual(expected)
	refuse = true
	local ok, failure = pcall(read)
	expect(ok):toBe(false)
	expect(tostring(failure)):toContain "configured store unavailable"
	refuse = false
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	expect(binding.environment.method(run, "IsStudio")(run)):toBe(true)
	local store = binding.service "DataStoreService"
	expect(binding.environment.method(store, "GetDataStore")(store, "isolated")):toBe "configured store"
	expect((pcall(function()
		return binding.service("Workspace").GetServerTimeNow
	end))):toBe(false)
	release()
end)

it("place services follow virtual time and input while retaining content URIs", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["clock.luau"] = "return function() return workspace:GetServerTimeNow() end",
		["input.luau"] = "return function() return game:GetService('UserInputService'):GetLastInputType() end",
		["mesh.luau"] = "return game:GetService('AssetService'):CreateMeshPartAsync(Content.fromUri('rbxassetid://123')).MeshId",
		["empty.luau"] = "return game:GetService('AssetService'):CreateMeshPartAsync(Content.none)",
	}, { "DataModel", "RunService", "Workspace", "UserInputService", "AssetService" }, { engine = binding })
	local clock = method(fixture.runtime.requireInstance(fixture.module("Clock", "clock.luau")))
	local input = method(fixture.runtime.requireInstance(fixture.module("Input", "input.luau")))
	local start = number(clock())
	fixture.runtime.step(0.25)
	expect(number(clock()) - start):toBe(0.25)
	expect(input()):toBe(binding.datatypes.Enum.UserInputType.None)
	local service = binding.service "UserInputService"
	local event = binding.newInstance("InputObject", true)
	binding.environment.poke(event, "UserInputType", binding.datatypes.Enum.UserInputType.Touch)
	binding.environment.fire(service, "InputBegan", event, false)
	binding.environment.scheduler.drain(64)
	expect(input()):toBe(binding.datatypes.Enum.UserInputType.Touch)
	expect(binding.environment.connectionsOfInstance(service)):toBe(3)
	expect(fixture.runtime.requireInstance(fixture.module("Mesh", "mesh.luau"))):toBe "rbxassetid://123"
	expect((pcall(fixture.runtime.requireInstance, fixture.module("Empty", "empty.luau")))):toBe(false)
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	expect(binding.environment.connectionsOfInstance(service)):toBe(0)
end)

it("project paths resolve beside the project and retain absolute source paths", function()
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
				listDirectory = function(): { { name: string, type: string } }
					return {}
				end,
			},
		})
		local value = assert(fixture.engine.service("ReplicatedStorage"):FindFirstChild "Value")
		expect(value.ClassName):toBe "ModuleScript"
		expect(mounted.sources[value]):toBe(expected)
	end
end)
it("bundled place clients run requested source with bounded frame stepping", function()
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
	local result: VM.Value = nil
	local env = bridge.environment
	local render = fixture.engine.environment.event(fixture.engine.service "RunService", "RenderStepped")
	render:Connect(function()
		table.insert(order, "render")
	end)
	env.scheduler.spawnTagged({ context = "client", source = "fixture/client.luau" }, function()
		result = fixture.runtime.requireInstance(module)
	end)
	expect(result):toBe(nil)
	fixture.runtime.step(1 / 60)
	expect(result):toBe "client-ready"
	expect(order):toEqual { "layout", "render" }
	expect(#env.errors):toBe(0)
	expect(#fixture.engine.diagnostics):toBe(0)
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	bridge.close()
end)
it("a signal callback requires modules in the context of the script that connected it", function()
	local bridge = Lute.fixture.bridge(nil, { handlerErrors = "raise" })
	local fixture = sourceFixture({
		["fixture/shared.luau"] = "return {}",
		["fixture/client.luau"] = [[
local first = require("./shared")
local result = { same = nil }
game:GetService("RunService").RenderStepped:Connect(function()
	result.same = require("./shared") == first
end)
return result
]],
	}, { "DataModel", "RunService", "Players", "HttpService" }, {
		engine = bridge.placeEngine(),
		client = { name = "Fixture", userId = 7, viewport = { x = 640, y = 480 } },
	})
	fixture.module("shared", "fixture/shared.luau")
	local module = fixture.module("Client", "fixture/client.luau")
	local result: VM.Value = nil
	bridge.environment.scheduler.spawnTagged({ context = "client", source = "fixture/client.luau" }, function()
		result = fixture.runtime.requireInstance(module)
	end)
	fixture.runtime.step(1 / 60)
	expect(field(result, "same")):toBe(true)
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	bridge.close()
end)
it("place frame readers fail closed before publishing render events", function()
	local frames = 0
	local fixture = sourceFixture({}, nil, {
		beforeRender = function()
			error "layout reader failure"
		end,
	})
	local render = fixture.engine.environment.event(fixture.engine.service "RunService", "RenderStepped")
	render:Connect(function()
		frames += 1
	end)
	local ok, failure = pcall(function(): unknown
		fixture.runtime.step(1 / 60)
		return nil
	end)
	expect(ok):toBe(false)
	expect(tostring(failure)):toContain "layout reader failure"
	expect(frames):toBe(0)
	for _, duration in { -1, math.huge, math.nan } do
		expect((pcall(fixture.runtime.step, duration))):toBe(false)
	end
end)
it("modeled preload reports every requested content as fetched", function()
	local fixture = sourceFixture({}, { "DataModel", "ContentProvider" })
	local service = fixture.engine.service "ContentProvider"
	local preload = fixture.engine.environment.method(service, "PreloadAsync")
	local seen: { string } = {}
	local statuses: { unknown } = {}
	local function callback(asset: string, status: unknown)
		table.insert(seen, asset)
		table.insert(statuses, status)
	end
	preload(service, {}, callback)
	expect(#seen):toBe(0)
	local image = fixture.engine.newInstance "ImageLabel"
	fixture.engine.environment.poke(image, "Image", "rbxassetid://2")
	local empty = fixture.engine.newInstance "ImageLabel"
	preload(service, { "rbxassetid://1", image, empty }, callback)
	expect(table.find(seen, "rbxassetid://1") ~= nil):toBe(true)
	expect(table.find(seen, "rbxassetid://2") ~= nil):toBe(true)
	for _, status in statuses do
		expect(tostring(status)):toBe "Enum.AssetFetchStatus.Success"
	end
end)
it("services start with the property values Studio 0.744 reports", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local gui = binding.service "GuiService"
	local input = binding.service "UserInputService"
	expect(binding.environment.propertyOf(gui, "TouchControlsEnabled")):toBe(true)
	expect(binding.environment.propertyOf(gui, "GuiNavigationEnabled")):toBe(true)
	expect(binding.environment.propertyOf(gui, "MenuIsOpen")):toBe(false)
	expect(binding.environment.propertyOf(input, "MouseIconEnabled")):toBe(true)
end)
it("the device simulator applies captured Studio device facts", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["desktop.luau"] = [[
				local input = game:GetService("UserInputService")
				return { input.PreferredInput.Name, input.TouchEnabled, input.KeyboardEnabled, input.MouseEnabled, input.GamepadEnabled }
			]],
		["pads.luau"] = [[
				return function(id)
					game:GetService("StudioDeviceSimulatorService"):SetDeviceAsync(id)
					local input = game:GetService("UserInputService")
					local connected = {}
					for _, pad in input:GetConnectedGamepads() do
						table.insert(connected, pad.Name)
					end
					return {
						#input:GetNavigationGamepads(),
						table.concat(connected, ","),
						input:GetGamepadConnected(Enum.UserInputType.Gamepad1),
						input:GamepadSupports(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA),
					}
				end
			]],
		["shape.luau"] = [[
				return function()
					local simulator = game:GetService("StudioDeviceSimulatorService")
					local gui = game:GetService("GuiService")
					local function facts()
						local size = workspace.CurrentCamera.ViewportSize
						local none = gui:GetInsetArea(Enum.ScreenInsets.None)
						local core = gui:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
						local orientation = simulator:GetOrientationAsync()
						return string.format("%d,%d [%d,%d,%d,%d] [%d,%d,%d,%d] %s", size.X, size.Y, none.Min.X, none.Min.Y, none.Max.X, none.Max.Y, core.Min.X, core.Min.Y, core.Max.X, core.Max.Y, orientation.Name)
					end
					local out = {}
					simulator:SetDeviceAsync("iphone_14")
					simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
					table.insert(out, facts())
					simulator:SetDeviceAsync("iphone_14")
					simulator:SetResolutionAsync(390, 844)
					table.insert(out, facts())
					simulator:SetDeviceAsync("hd_1080")
					simulator:SetResolutionAsync(800, 600)
					table.insert(out, facts())
					table.insert(out, (pcall(simulator.SetOrientationAsync, simulator, Enum.ScreenOrientation.Portrait)))
					simulator:SetDeviceAsync("iphone_14")
					table.insert(out, (pcall(simulator.SetOrientationAsync, simulator, "Landscape")))
					return out
				end
			]],
		["switch.luau"] = [[
				return function(id)
					game:GetService("StudioDeviceSimulatorService"):SetDeviceAsync(id)
					local gui, input = game:GetService("GuiService"), game:GetService("UserInputService")
					local topLeft = gui:GetGuiInset()
					local core = gui:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets)
					local none = gui:GetInsetArea(Enum.ScreenInsets.None)
					local viewport = workspace.CurrentCamera.ViewportSize
					return {
						gui:IsTenFootInterface(), input.PreferredInput.Name, input.TouchEnabled, input.GamepadEnabled,
						topLeft.Y, core.Width, none.Min.X, viewport.X, viewport.Y,
					}
				end
			]],
	}, { "DataModel", "GuiService", "UserInputService", "StudioDeviceSimulatorService" }, {
		engine = binding,
		client = { name = "Device", userId = 1, viewport = { x = 800, y = 600 } },
	})
	local desktop = fixture.runtime.requireInstance(fixture.module("Desktop", "desktop.luau"))
	local expectedDesktop: { unknown } = { "KeyboardAndMouse", false, true, true, false }
	expect(desktop):toEqual(expectedDesktop)
	local pads = method(fixture.runtime.requireInstance(fixture.module("Pads", "pads.luau")))
	local xboxPads: { unknown } = { 8, "Gamepad1", true, false }
	local phonePads: { unknown } = { 8, "", false, false }
	expect(pads "xbox"):toEqual(xboxPads)
	expect(pads "iphone_14"):toEqual(phonePads)
	local switch = method(fixture.runtime.requireInstance(fixture.module("Switch", "switch.luau")))
	local xbox: { unknown } = { true, "Gamepad", false, true, 58, 1919, 0, 1919, 1080 }
	local phone: { unknown } = { false, "Touch", true, false, 58, 749, -47, 749, 389 }
	expect(switch "xbox"):toEqual(xbox)
	expect(switch "iphone_14"):toEqual(phone)
	expect((pcall(switch, "unknown_device"))):toBe(false)
	local shape = method(fixture.runtime.requireInstance(fixture.module("Shape", "shape.luau")))
	local captured: { unknown } = {
		"389,762 [0,-105,389,738] [0,0,389,704] Portrait",
		"295,843 [-47,-58,342,785] [0,0,295,785] LandscapeLeft",
		"799,600 [0,-58,799,542] [0,0,799,542] LandscapeLeft",
		false,
		false,
	}
	expect(shape()):toEqual(captured)
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
end)

it("desktop clients report no ten-foot UI, no held buttons and the viewport inset area", function()
	local binding = Lute.fixture.bridge().placeEngine()
	local fixture = sourceFixture({
		["tenFoot.luau"] = "return game:GetService('GuiService'):IsTenFootInterface()",
		["gamepad.luau"] = "return game:GetService('UserInputService'):IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)",
		["mouse.luau"] = "return #game:GetService('UserInputService'):GetMouseButtonsPressed()",
		["area.luau"] = "local area = game:GetService('GuiService'):GetInsetArea(Enum.ScreenInsets.None) return { area.Width, area.Height }",
	}, { "DataModel", "GuiService", "UserInputService" }, {
		engine = binding,
		client = { name = "Desk", userId = 1, viewport = { x = 800, y = 600 } },
	})
	expect(fixture.runtime.requireInstance(fixture.module("TenFoot", "tenFoot.luau"))):toBe(false)
	expect(fixture.runtime.requireInstance(fixture.module("Gamepad", "gamepad.luau"))):toBe(false)
	expect(fixture.runtime.requireInstance(fixture.module("Mouse", "mouse.luau"))):toBe(0)
	expect(fixture.runtime.requireInstance(fixture.module("Area", "area.luau"))):toEqual { 800, 600 }
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
end)

it("CollectionService shares Instance tags and matches native DataModel entry and pending removal", function()
	local fixture = sourceFixture({}, { "DataModel", "RunService", "HttpService", "CollectionService" })
	local env, game = fixture.engine.environment, fixture.engine.game
	local service = fixture.engine.service "CollectionService"
	local get = env.method(service, "GetTagged")
	local added = env.method(service, "GetInstanceAddedSignal")(service, "Hot")
	local removed = env.method(service, "GetInstanceRemovedSignal")(service, "Hot")
	local events: { string } = {}
	local function subscribe(signal: Environment.Signal, name: string)
		signal:Connect(function(value: unknown)
			local object = Environment.assertInstance(value)
			table.insert(
				events,
				name
					.. ":"
					.. tostring(object:HasTag "Hot")
					.. ":"
					.. tostring(object:IsDescendantOf(game))
					.. ":"
					.. #record(get(service, "Hot"))
			)
		end)
	end
	local addedSignal = assert(fixture.runtime.tagAdded.Hot)
	local removedSignal = assert(fixture.runtime.tagRemoved.Hot)
	expect(added == addedSignal):toBe(true)
	expect(removed == removedSignal):toBe(true)
	subscribe(addedSignal, "added")
	subscribe(removedSignal, "removed")
	local object = fixture.engine.newInstance "Folder"
	object:AddTag "Hot"
	expect(get(service, "Hot")):toEqual {}
	object.Parent = game
	object:AddTag "Hot"
	local addTag = env.method(service, "AddTag")
	local removeTag = env.method(service, "RemoveTag")
	removeTag(service, object, "Hot")
	addTag(service, object, "Hot")
	addTag(service, object, "Hot")
	object.Parent = nil
	object.Parent = game
	object:RemoveTag "Hot"
	object:AddTag "Hot"
	object:Destroy()
	expect(events):toEqual {
		"added:true:true:1",
		"removed:false:true:0",
		"added:true:true:1",
		"removed:true:true:0",
		"added:true:true:1",
		"removed:false:true:0",
		"added:true:true:1",
		"removed:true:true:0",
	}
	expect(object:HasTag "Hot"):toBe(true)
	expect(get(service, "Hot")):toEqual {}
	table.clear(events)
	local parent = fixture.engine.newInstance "Folder"
	local child = fixture.engine.newInstance "Folder"
	parent:AddTag "Hot"
	child:AddTag "Hot"
	child.Parent = parent
	parent.Parent = game
	expect(events):toEqual { "added:true:true:2", "added:true:true:2" }
	table.clear(events)
	local container = fixture.engine.newInstance "Folder"
	container.Parent = game
	parent.Parent = container
	expect(events):toEqual {}
	parent.Parent = nil
	expect(events):toEqual { "removed:true:true:1", "removed:true:true:0" }
	game:AddTag "Hot"
	expect(get(service, "Hot")):toEqual { game }
	game:RemoveTag "Hot"
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	expect(env.liveConnections()):toBe(0)
end)
it("ModuleScript type and typeof preserve native identities without classifying spoofed tables", function()
	local fixture = sourceFixture {
		["fixture/Kinds.luau"] = "return {type(script),typeof(script),type(shared.object),typeof(shared.object),type(shared.signal),typeof(shared.signal),type(shared.connection),typeof(shared.connection),type({__state={class={instance=true}}}),typeof({__state={class={instance=true}}})}",
	}
	local env = fixture.engine.environment
	local spec: Environment.ClassSpec = { super = "Object", creatable = false }
	env.defineClass("VirtualInput", spec)
	local object = env.createEngineObject "VirtualInput"
	local signal = env.newSignal()
	local connection = signal:Connect(function() end)
	fixture.runtime.globals.shared = { object = object, signal = signal, connection = connection }
	local module = fixture.module("Kinds", "fixture/Kinds.luau")
	expect(fixture.runtime.requireInstance(module)):toEqual {
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
end)
it("ModuleScript caches by instance identity while sharing source bytecode", function()
	local fixture = sourceFixture {
		["value.luau"] = "shared.executions = (shared.executions or 0) + 1; return { execution = shared.executions }",
	}
	local first = fixture.module("First", "value.luau")
	local second = fixture.module("Second", "value.luau")
	local firstValue = fixture.runtime.requireInstance(first)
	expect(fixture.runtime.requireInstance(first) == firstValue):toBe(true)
	expect(firstValue == fixture.runtime.requireInstance(second)):toBe(false)
	expect(Environment.read(fixture.runtime.globals.shared, "executions")):toBe(2)
	expect(fixture.compilations()):toBe(1)
end)

it("ModuleScript resolves init children sibling paths and parent paths on the mounted tree", function()
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
	local packageValue = fixture.runtime.requireInstance(package)
	expect(field(packageValue, "relative")):toBe(7)
	expect(field(packageValue, "own")):toBe(42)
	local mainValue = fixture.runtime.requireInstance(main)
	expect(field(mainValue, "sibling")):toBe(42)
	expect(field(mainValue, "parent")):toBe(7)
end)

it("mounted relative requires traverse repeated parent and current segments without changing identity", function()
	local fixture = sourceFixture {
		["value.luau"] = "return {}",
		["deep.luau"] = 'return { require("../../Shared"), require("./../../Shared"), require(".././../Shared") }',
		["escape.luau"] = 'return require("../../../../Missing")',
	}
	local outer = fixture.module("Outer", "value.luau")
	local inner = fixture.module("Inner", "value.luau", outer)
	local deep = fixture.module("Deep", "deep.luau", inner)
	local shared = fixture.module("Shared", "value.luau")
	local expected = fixture.runtime.requireInstance(shared)
	local values = record(fixture.runtime.requireInstance(deep))
	expect(#values):toBe(3)
	for _, value in values do
		expect(value == expected):toBe(true)
	end
	local escape = fixture.module("Escape", "escape.luau", inner)
	local ok = pcall(fixture.runtime.requireInstance, escape)
	expect(ok):toBe(false)
	expect(fixture.engine.diagnostics[1].text):toContain "place runtime cannot resolve require"
end)

it("HttpService encodes nil as JSON null without requiring host serializer support", function()
	local fixture = sourceFixture {
		["json.luau"] = 'local http = game:GetService("HttpService"); return { http:JSONEncode(nil), http:JSONEncode(false), http:JSONEncode("hello"), http:JSONEncode({1, 2}) }',
	}
	local value = fixture.runtime.requireInstance(fixture.module("Json", "json.luau"))
	expect(value):toEqual { "null", "false", '"hello"', "[1,2]" }
end)

it("HttpService preserves native null values and table encoding rules", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local fixture = sourceFixture({
		["json-values.luau"] = require "./fixtures/http-json-values",
	}, nil, { engine = bridge.placeEngine() })
	local ok, result = pcall(fixture.runtime.requireInstance, fixture.module("JsonValues", "json-values.luau"))
	expect(fixture.engine.diagnostics):toEqual {}
	expect(ok and result):toBe(true)
end)

it("ModuleScript repeats runtime and compile errors without leaving a loading cache entry", function()
	local fixture = sourceFixture {
		["failure.luau"] = 'error("module fixture failure")',
		["syntax.luau"] = "return (",
	}
	for _, name in { "failure", "syntax" } do
		local object = fixture.module(name, name .. ".luau")
		local errors: { string } = {}
		for _ = 1, 2 do
			local ok, failure = pcall(fixture.runtime.requireInstance, object)
			expect(ok):toBe(false)
			table.insert(errors, tostring(failure))
		end
		expect(errors[1]):toBe(errors[2])
		expect(errors[1]):toContain "Requested module experienced an error while loading"
	end
	expect(#fixture.engine.diagnostics):toBe(2)
	expect(fixture.engine.diagnostics[1].source):toBe "failure.luau"
	expect(fixture.engine.diagnostics[1].text):toContain "module fixture failure"
	expect(fixture.engine.diagnostics[2].source):toBe "syntax.luau"
	local missing = fixture.module("Missing", "absent.luau")
	fixture.mounted.sources[missing] = nil
	expect((pcall(fixture.runtime.requireInstance, missing))):toBe(false)
	expect((pcall(fixture.runtime.requireInstance, fixture.engine.game))):toBe(false)
end)

it("place runtime installs only selected method doubles on existing and new service instances", function()
	local fixture = sourceFixture {}
	local get = fixture.engine.environment.method(fixture.engine.game, "GetService")
	expect(get(fixture.engine.game, "RunService") == fixture.engine.service "RunService"):toBe(true)
	expect(fixture.engine.service("ContentProvider").PreloadAsync):toBe(nil)
	for _, close in fixture.runtime.closeHandlers do
		close()
	end
	expect(fixture.engine.service("HttpService").JSONEncode):toBe(nil)
end)

it("mounts implicit project datatype values and attributes on roots, services and children", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local project = {
		tree = {
			["$attributes"] = { rootMarker = "root" },
			Lighting = {
				["$properties"] = {
					Ambient = { 0.2, 0.3, 0.4 },
					OutdoorAmbient = { Color3 = { 0.4, 0.5, 0.6 } },
				},
			},
			Workspace = {
				["$attributes"] = { serviceMarker = true },
				Part = {
					["$className"] = "Part",
					["$attributes"] = { childMarker = 42 },
					["$properties"] = {
						Anchored = { Bool = true },
						CanCollide = { Bool = false },
						Transparency = { Float32 = 0.25 },
						Size = { 4, 2, 6 },
						CFrame = { 1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
					},
				},
				Image = {
					["$className"] = "ImageLabel",
					["$properties"] = { AnchorPoint = { 0.5, 0.25 }, ImageRectSize = { Vector2 = { 10, 20 } } },
				},
			},
		},
	}
	local fixtureHost = Lute.fixture.host
	local host: PlaceRuntime.Host<luau.Bytecode> = {
		readFile = function(): string
			return json.serialize(project)
		end,
		compile = fixtureHost.compile,
		load = fixtureHost.load,
		encodeJson = fixtureHost.encodeJson,
		decodeJson = fixtureHost.decodeJson,
	}
	Roblox.buildPlaceTree(engine, "fixture.project.json", {
		host = host,
		cache = Roblox.createPlaceCache(host),
		files = {
			exists = Lute.fixture.files.exists,
			fileType = Lute.fixture.files.fileType,
			listDirectory = Lute.fixture.files.listDirectory,
		},
	})
	local library = engine.datatypes
	expect(engine.game:GetAttribute "rootMarker"):toBe "root"
	expect(engine.service("Workspace"):GetAttribute "serviceMarker"):toBe(true)
	expect(engine.service("Lighting").Ambient):toBe(library.Color3.new(0.2, 0.3, 0.4))
	expect(engine.service("Lighting").OutdoorAmbient):toBe(library.Color3.new(0.4, 0.5, 0.6))
	local part = assert(engine.service("Workspace"):FindFirstChild "Part")
	expect(part:GetAttribute "childMarker"):toBe(42)
	expect(part.Size):toBe(library.Vector3.new(4, 2, 6))
	expect(part.CFrame):toBe(library.CFrame.new(1, 2, 3))
	expect(part.Anchored):toBe(true)
	expect(part.CanCollide):toBe(false)
	expect(part.Transparency):toBe(0.25)
	local image = assert(engine.service("Workspace"):FindFirstChild "Image")
	expect(image.AnchorPoint):toBe(library.Vector2.new(0.5, 0.25))
	expect(image.ImageRectSize):toBe(library.Vector2.new(10, 20))
end)

it("boots mounted scripts and requires modules without accepting invalid targets", function()
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
	local host: PlaceRuntime.Host<luau.Bytecode> = {
		readFile = function(path: string): string
			local contents = files[path]
			assert(type(contents) == "string")
			return contents
		end,
		compile = luau.compile,
		load = function(code: luau.Bytecode, name: string, environment: { [string]: unknown }): () -> VM.Value
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
			listDirectory = function(): { { name: string, type: string } }
				return {}
			end,
		},
	})
	expect(#report.diagnostics):toBe(0)
	expect(Environment.read(report.runtime.globals.shared, "answer")):toBe(42)
	expect(report.engine.game.PlaceId):toBe(2)
	local types = report.engine.datatypes
	expect(report.engine.service("Lighting").Ambient):toBe(types.Color3.new(0.2, 0.3, 0.4))
	expect(report.engine.service("Lighting").LightingStyle):toBe(types.Enum.LightingStyle.Realistic)
	expect(report.engine.game.RunService):toBe(report.engine.service "RunService")
	local stand = assert(report.engine.service("Workspace"):FindFirstChild "Stand")
	expect(stand.Size):toBe(types.Vector3.new(4, 2, 6))
	expect(stand.Shape):toBe(types.Enum.PartType.Block)
	expect(stand.CFrame):toBe(types.CFrame.new(1, 2, 3))
	expect(report.player.Character ~= nil):toBe(true)
	expect((pcall(report.runtime.requireInstance, report.player))):toBe(false)
	expect((pcall(report.runtime.requireInstance, "@missing/module"))):toBe(false)
	local invalidColor: { unknown } = { 0.2, "invalid", 0.4 }
	files["fixture.json"] = json.serialize {
		tree = {
			Lighting = { ["$properties"] = { Ambient = { Color3 = invalidColor } } },
		},
	}
	expect((pcall(Roblox.buildPlaceTree, report.engine, "fixture.json", {
		host = host,
		cache = Roblox.createPlaceCache(host),
		files = {
			exists = function()
				return false
			end,
			fileType = function()
				return "file"
			end,
			listDirectory = function(): { { name: string, type: string } }
				return {}
			end,
		},
	}))):toBe(false)
end)

return nil
