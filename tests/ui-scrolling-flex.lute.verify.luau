--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local out = {}
local function case(name, class, pad, flex, kids)
	local root = Instance.new("Frame"); root.Size = UDim2.fromOffset(400, 300); root.Parent = g
	local s = Instance.new(class); s.Size = UDim2.fromOffset(0, 50); s.AutomaticSize = Enum.AutomaticSize.X
	if class == "ScrollingFrame" then s.CanvasSize = UDim2.new() end
	local u = Instance.new("UIPadding"); u.PaddingLeft = UDim.new(0, pad); u.PaddingRight = UDim.new(0, pad); u.PaddingTop = UDim.new(0, pad); u.Parent = s
	local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection.Horizontal; l.Padding = UDim.new(0, 4); l.HorizontalFlex = Enum.UIFlexAlignment[flex]; l.Parent = s
	local made = {}
	for i, k in kids do
		local f = Instance.new("Frame"); f.Size = UDim2.fromOffset(k, 20); f.LayoutOrder = i
		local fi = Instance.new("UIFlexItem"); fi.FlexMode = Enum.UIFlexMode.Grow; fi.Parent = f
		f.Parent = s; made[i] = f
	end
	s.Parent = root
	task.wait(); task.wait()
	local got = {}
	for _, f in made do table.insert(got, `{f.AbsoluteSize.X}@{f.AbsolutePosition.X - s.AbsolutePosition.X}`) end
	table.insert(out, `{name}: abs={s.AbsoluteSize.X} kids=` .. table.concat(got, " "))
	root:Destroy()
end
case("SF pad3 fill", "ScrollingFrame", 3, "Fill", {69, 74})
case("SF pad3 none", "ScrollingFrame", 3, "None", {69, 74})
case("Frame pad3 fill", "Frame", 3, "Fill", {69, 74})
case("SF pad0 fill", "ScrollingFrame", 0, "Fill", {69, 74})
case("SF pad10 fill", "ScrollingFrame", 10, "Fill", {69, 74})
g:Destroy()
local want = [[
SF pad3 fill: abs=153 kids=72@3 77@79
SF pad3 none: abs=153 kids=72@3 77@79
Frame pad3 fill: abs=153 kids=69@3 74@76
SF pad0 fill: abs=147 kids=69@0 74@73
SF pad10 fill: abs=167 kids=79@10 84@93
]]
local got = table.concat(out, "\n") .. "\n"
assert(got == want, got)
return true
]==]

local function run(source: string): Test.Body
	return function(own)
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
			client = { name = "ScaledPadding", userId = 1, viewport = { x = 800, y = 600 } },
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
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-automatic-scaled-padding" }, function()
			complete = Lute.chunk.load(source, { environment = runtime.globals })() == true
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
	end
end
it("flex items in a padded ScrollingFrame grow over the unpadded width as Studio 0.744 does", run(probe))

return nil
