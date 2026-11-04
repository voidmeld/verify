--!strict

local Test = require "./harness"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local Values = require "../src/roblox/ui-values"
local Bdd = require "../src/bdd"
local PlaceRuntime = require "../src/roblox/place-runtime"

local function fixture(own: Bdd.Own, client: PlaceRuntime.Client?)
	local roots: { Roblox.Instance } = {}
	local runtime: Roblox.PlaceRuntime? = nil
	local bridge = Lute.fixture.bridge(nil, {
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				local viewport = assert(runtime).device().viewport
				return { X = viewport[1], Y = viewport[2] }
			end,
			screenArea = function(screen)
				return assert(runtime).screenArea(screen)
			end,
		},
	})
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local created = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
		client = client or { name = "Layout", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	runtime = created
	own(function()
		for index = #created.closeHandlers, 1, -1 do
			created.closeHandlers[index]()
		end
	end)
	table.insert(roots, assert(assert(created.localPlayer):FindFirstChild "PlayerGui"))
	return bridge, engine, created, roots[1]
end

Test.it("a desktop fixture exposes a medium display class before a runtime is installed", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	Test.expect(engine.service("GuiService").ViewportDisplaySize):toBe(engine.datatypes.Enum.DisplaySize.Medium)
end)

Test.it("client viewports and captured text bounds produce nonzero hugging geometry", function(own)
	local bridge, engine, runtime, playerGui = fixture(own)
	local library = engine.datatypes
	local camera = bridge.environment.assertInstance(engine.service("Workspace").CurrentCamera)
	Test.expect(camera.ViewportSize):toBe(library.Vector2.new(800, 600))
	local screen = engine.newInstance "ScreenGui"
	screen.Parent = playerGui
	local frame = engine.newInstance "Frame"
	frame.Size, frame.Parent = library.UDim2.fromScale(1, 1), screen
	local label = engine.newInstance "TextLabel"
	label.Size, label.AutomaticSize = library.UDim2.fromOffset(0, 0), library.Enum.AutomaticSize.XY
	label.FontFace, label.TextSize, label.Text = library.Font.fromEnum(library.Enum.Font.BuilderSans), 20, "Hello"
	label.Parent = frame
	Test.expect(frame.AbsoluteSize):toBe(library.Vector2.new(800, 600))
	local before = Values.vector(label.TextBounds)
	Test.expect(before.X):toBeGreaterThan(0)
	Test.expect(before.Y):toBeGreaterThan(0)
	Test.expect(label.AbsoluteSize):toBe(label.TextBounds)
	bridge.environment.scheduler.delay(0.1, function()
		label.Text = "Hello world"
	end)
	runtime.step(1 / 30)
	Test.expect(Values.vector(label.TextBounds).X):toBe(before.X)
	runtime.step(0.1)
	Test.expect(Values.vector(label.TextBounds).X):toBeGreaterThan(before.X)
	Test.expect(label.AbsoluteSize):toBe(label.TextBounds)
	Test.expect(engine.diagnostics):toEqual {}
end)

Test.it("captured devices expose their display classes across viewport changes", function(own)
	local bridge, engine, runtime = fixture(own, {
		name = "Display",
		userId = 1,
		viewport = { x = 800, y = 600 },
		displaySize = "Large",
	})
	local gui = engine.service "GuiService"
	Test.expect(gui.ViewportDisplaySize):toBe(engine.datatypes.Enum.DisplaySize.Large)
	local complete = false
	bridge.environment.scheduler.spawnTagged({ context = "client", source = "device-display-size" }, function()
		complete = Lute.chunk.load(require "./fixtures/device-display-size", { environment = runtime.globals })()
			== true
	end)
	for _ = 1, 120 do
		if complete or #bridge.environment.scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 30)
	end
	Test.expect(bridge.environment.scheduler.failures):toEqual {}
	Test.expect(complete):toBe(true)
	Test.expect(gui.ViewportDisplaySize):toBe(engine.datatypes.Enum.DisplaySize.Large)
end)

Test.it("explicit service doubles provide protected leave events and mobile platform answers", function(own)
	local library = Roblox.reflectionSnapshot.library(Lute.fixture.load())
	local bridge = Lute.fixture.bridge(nil, {
		classes = {
			GuiService = { events = { "ShowLeaveConfirmation" } },
			UserInputService = {
				methods = {
					GetPlatform = function()
						return library.Enum.Platform.IOS
					end,
				},
			},
		},
	})
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local gui, input = engine.service "GuiService", engine.service "UserInputService"
	local calls = 0
	bridge.environment.event(gui, "ShowLeaveConfirmation"):Connect(function()
		calls += 1
	end)
	bridge.environment.fire(gui, "ShowLeaveConfirmation")
	bridge.environment.scheduler.drain(64)
	bridge.environment.poke(input, "TouchEnabled", true)
	bridge.environment.poke(input, "MouseEnabled", false)
	Test.expect(calls):toBe(1)
	Test.expect(input.TouchEnabled):toBe(true)
	Test.expect(input.MouseEnabled):toBe(false)
	Test.expect(bridge.environment.method(input, "GetPlatform")(input)):toBe(library.Enum.Platform.IOS)
end)

return nil
