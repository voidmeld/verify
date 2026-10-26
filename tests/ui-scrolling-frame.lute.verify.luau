--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local function scrollingFixture()
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 1000, Y = 1000 }
			end,
		},
	})
	local root = bridge.environment.createInstance("ScreenGui", { Name = "ScrollScreen" })
	table.insert(roots, root)
	local frame = bridge.environment.createInstance("ScrollingFrame", {
		Name = "ScrollBounds",
		Parent = root,
		Size = Roblox.datatypes.UDim2.fromOffset(1000, 1000),
		CanvasSize = Roblox.datatypes.UDim2.fromOffset(772, 772),
		CanvasPosition = Roblox.datatypes.Vector2.new(193, 193),
	})
	return bridge, root, frame
end

it("refuses to clamp poked scrolling bounds with an unmeasured zero canvas before publishing geometry", function(own)
	local bridge, root, frame = scrollingFixture()
	own(bridge.close)
	local env = bridge.environment
	local V = Roblox.datatypes.Vector2
	local rootSize = env.propertyOf(root, "AbsoluteSize")
	env.poke(frame, "AbsoluteSize", V.new(386, 386))
	env.poke(frame, "AbsoluteWindowSize", V.new(386, 386))
	expect(env.propertyOf(frame, "AbsoluteCanvasSize")):toEqual(V.zero)
	local layout = assert(bridge.layout)
	local ok, message = pcall(function(): unknown
		layout.step()
		return nil
	end)
	expect(ok):toBe(false)
	for _, part in
		{
			"unsupported_ui_layout",
			"ScrollScreen.ScrollBounds",
			"stale/poked",
			"AbsoluteSize=(386, 386), computed=(1000, 1000)",
			"AbsoluteWindowSize=(386, 386), computed=(1000, 1000)",
			"AbsoluteCanvasSize=(0, 0), computed=(1000, 1000)",
			"CanvasPosition=(193, 193), computed=(0, 0)",
			"author Size and CanvasSize",
		}
	do
		expect(tostring(message)):toContain(part)
	end
	expect(frame.CanvasPosition):toEqual(V.new(193, 193))
	expect(env.propertyOf(frame, "AbsoluteSize")):toEqual(V.new(386, 386))
	expect(env.propertyOf(frame, "AbsoluteWindowSize")):toEqual(V.new(386, 386))
	expect(env.propertyOf(frame, "AbsoluteCanvasSize")):toEqual(V.zero)
	expect(env.propertyOf(root, "AbsoluteSize")):toEqual(rootSize)
	frame.Size = Roblox.datatypes.UDim2.fromOffset(386, 386)
	layout.step()
	expect(frame.CanvasPosition):toEqual(V.new(193, 193))
	expect(frame.AbsoluteCanvasSize):toEqual(V.new(772, 772))
end)

it("detects scrolling geometry poked after a successful layout pass", function(own)
	for _, property in { "AbsoluteSize", "AbsoluteWindowSize", "AbsoluteCanvasSize" } do
		local bridge, _, frame = scrollingFixture()
		own(bridge.close)
		local V = Roblox.datatypes.Vector2
		frame.Size = Roblox.datatypes.UDim2.fromOffset(386, 386)
		local layout = assert(bridge.layout)
		layout.step()
		bridge.environment.poke(frame, property, V.zero)
		frame.CanvasPosition = V.new(900, 900)
		expect(layout.step):toThrow("stale/poked " .. property)
		expect(frame.CanvasPosition):toEqual(V.new(900, 900))
		expect(bridge.environment.propertyOf(frame, property)):toEqual(V.zero)
	end
end)

it("clamps fully measured scrolling frames on the first pass and after authored resizing", function(own)
	local bridge, _, frame = scrollingFixture()
	own(bridge.close)
	local D = Roblox.datatypes
	frame.Size = D.UDim2.fromOffset(386, 386)
	frame.CanvasPosition = D.Vector2.new(900, 900)
	local child = bridge.environment.createInstance("Frame", {
		Parent = frame,
		Size = D.UDim2.fromOffset(10, 10),
	})
	local layout = assert(bridge.layout)
	layout.step()
	expect(frame.CanvasPosition):toEqual(D.Vector2.new(386, 386))
	expect(frame.AbsoluteCanvasSize):toEqual(D.Vector2.new(772, 772))
	expect(child.AbsolutePosition):toEqual(D.Vector2.new(-386, -386))
	frame.CanvasPosition = D.Vector2.new(193, 193)
	layout.step()
	expect(frame.CanvasPosition):toEqual(D.Vector2.new(193, 193))
	frame.Size = D.UDim2.fromOffset(1000, 1000)
	layout.step()
	expect(frame.CanvasPosition):toEqual(D.Vector2.zero)
	expect(child.AbsolutePosition):toEqual(D.Vector2.zero)
end)

local probe = [==[
local RS = game:GetService("RunService")
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local out = {}
local root = Instance.new("Frame"); root.Size = UDim2.fromOffset(1000, 1000); root.Parent = g
local function case(name, props, kids, canvasPos)
	local s = Instance.new("ScrollingFrame"); s.Size = UDim2.fromOffset(300, 200); s.Position = UDim2.fromOffset(10, 10)
	for k, v in props do s[k] = v end
	s.Parent = root
	local made = {}
	for i, k in kids do
		local c = Instance.new(k.class or "Frame")
		if c:IsA("GuiObject") then c.Size = k.size; c.Position = k.pos or UDim2.new(); c.LayoutOrder = i end
		c.Parent = s; made[i] = c
	end
	RS.RenderStepped:Wait(); RS.RenderStepped:Wait()
	if canvasPos then s.CanvasPosition = canvasPos; RS.RenderStepped:Wait(); RS.RenderStepped:Wait() end
	local parts = {}
	for i, c in made do if c:IsA("GuiObject") then table.insert(parts, `c{i}={c.AbsoluteSize.X},{c.AbsoluteSize.Y}@{c.AbsolutePosition.X - s.AbsolutePosition.X},{c.AbsolutePosition.Y - s.AbsolutePosition.Y}`) end end
	table.insert(out, string.format("%s: win=%s canvas=%s pos=%s %s", name, tostring(s.AbsoluteWindowSize), tostring(s.AbsoluteCanvasSize), tostring(s.CanvasPosition), table.concat(parts, " ")))
	s:Destroy()
end
local tall = { size = UDim2.fromOffset(100, 500) }
local wide = { size = UDim2.fromOffset(500, 100) }
case("default", {}, { { size = UDim2.fromScale(1, 0.5) } })
case("canvas 0,600 tall", { CanvasSize = UDim2.fromOffset(0, 600) }, { { size = UDim2.fromScale(1, 0.5) } })
case("canvas scale 1,2", { CanvasSize = UDim2.fromScale(1, 2) }, { { size = UDim2.fromScale(1, 0.5) } })
case("canvas 0,600 insetScrollBar", { CanvasSize = UDim2.fromOffset(0, 600), VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar }, { { size = UDim2.fromScale(1, 0.5) } })
case("canvas 0,100 insetScrollBar", { CanvasSize = UDim2.fromOffset(0, 100), VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar }, { { size = UDim2.fromScale(1, 0.5) } })
case("canvas 0,100 insetAlways", { CanvasSize = UDim2.fromOffset(0, 100), VerticalScrollBarInset = Enum.ScrollBarInset.Always }, { { size = UDim2.fromScale(1, 0.5) } })
case("auto Y list", { CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, { { class = "UIListLayout" }, tall, tall })
case("auto XY free", { CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.XY }, { wide, tall })
case("scroll y 150", { CanvasSize = UDim2.fromOffset(0, 600) }, { { size = UDim2.fromOffset(50, 50), pos = UDim2.fromOffset(0, 200) } }, Vector2.new(0, 150))
case("scroll clamp", { CanvasSize = UDim2.fromOffset(0, 600) }, { { size = UDim2.fromOffset(50, 50), pos = UDim2.fromOffset(0, 200) } }, Vector2.new(30, 900))
case("horizontal canvas insetScrollBar", { CanvasSize = UDim2.fromOffset(800, 0), HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar, ScrollingDirection = Enum.ScrollingDirection.X }, { { size = UDim2.fromScale(0.25, 1) } })
case("thickness 0 insetScrollBar", { CanvasSize = UDim2.fromOffset(0, 600), ScrollBarThickness = 0, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar }, { { size = UDim2.fromScale(1, 0.5) } })
case("both overflow insetScrollBar", { CanvasSize = UDim2.fromOffset(800, 600), VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar }, { { size = UDim2.fromScale(1, 1) } })
case("dirY canvas wide insetScrollBar", { CanvasSize = UDim2.fromOffset(800, 600), ScrollingDirection = Enum.ScrollingDirection.Y, VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, HorizontalScrollBarInset = Enum.ScrollBarInset.ScrollBar }, { { size = UDim2.fromScale(1, 1) } })
case("canvas scale fits", { CanvasSize = UDim2.fromScale(0.2, 0.1) }, { { size = UDim2.fromScale(1, 1) } })
g:Destroy()
local want = [[
default: win=287, 200 canvas=300, 2000 pos=0, 0 c1=300,1000@0,0
canvas 0,600 tall: win=287, 200 canvas=300, 600 pos=0, 0 c1=300,300@0,0
canvas scale 1,2: win=287, 187 canvas=1000, 2000 pos=0, 0 c1=1000,1000@0,0
canvas 0,600 insetScrollBar: win=287, 200 canvas=287, 600 pos=0, 0 c1=287,300@0,0
canvas 0,100 insetScrollBar: win=300, 200 canvas=300, 200 pos=0, 0 c1=300,100@0,0
canvas 0,100 insetAlways: win=300, 200 canvas=287, 200 pos=0, 0 c1=287,100@0,0
auto Y list: win=287, 200 canvas=300, 1000 pos=0, 0 c2=100,500@0,0 c3=100,500@0,500
auto XY free: win=287, 187 canvas=500, 500 pos=0, 0 c1=500,100@0,0 c2=100,500@0,0
scroll y 150: win=287, 200 canvas=300, 600 pos=0, 150 c1=50,50@0,50
scroll clamp: win=287, 200 canvas=300, 600 pos=0, 400 c1=50,50@0,-200
horizontal canvas insetScrollBar: win=300, 187 canvas=800, 187 pos=0, 0 c1=200,187@0,0
thickness 0 insetScrollBar: win=299, 200 canvas=299, 600 pos=0, 0 c1=299,300@0,0
both overflow insetScrollBar: win=287, 187 canvas=800, 600 pos=0, 0 c1=800,600@0,0
dirY canvas wide insetScrollBar: win=287, 200 canvas=800, 600 pos=0, 0 c1=800,600@0,0
canvas scale fits: win=300, 200 canvas=300, 200 pos=0, 0 c1=300,200@0,0
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
return true
]==]

it("ScrollingFrames size their window, canvas and scroll offset as Studio 0.744 does", function(own)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		layout = {
			roots = function()
				return roots
			end,
			viewport = function()
				return { X = 800, Y = 600 }
			end,
		},
	})
	own(function()
		bridge.close()
	end)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
		client = { name = "Scrolling", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	own(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	local playerGui = assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui")
	table.insert(roots, playerGui)
	local input = Roblox.inputHost.simulated(bridge.environment, {
		playerGui = playerGui,
		inputService = engine.service "UserInputService",
		layout = assert(bridge.layout),
		inset = function()
			return { X = 0, Y = 0 }
		end,
		library = Roblox.reflectionSnapshot.library(Lute.fixture.load()),
		activationWindowSeconds = 0.5,
		read = assert(bridge.ui).styled,
	})
	own(input.close)
	local complete = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-scrolling-frame" }, function()
		complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
	end)
	own(function()
		scheduler.cancel(thread)
	end)
	for _ = 1, 240 do
		if complete or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	expect(scheduler.failures):toEqual {}
	expect(engine.diagnostics):toEqual {}
	expect(complete):toBe(true)
end)

return nil
