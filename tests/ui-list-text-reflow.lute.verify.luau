--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local failures = {}
local function frame(props, parent, class) local f = Instance.new(class or "Frame"); for k, v in props do f[k] = v end; f.Parent = parent; return f end
for _, cfg in { {"Fill", UDim2.fromOffset(0, 0), Enum.AutomaticSize.Y}, {"Fill", UDim2.fromScale(1, 0), Enum.AutomaticSize.Y}, {"Shrink", UDim2.fromScale(1, 0), Enum.AutomaticSize.Y}, {"Grow", UDim2.fromOffset(100, 0), Enum.AutomaticSize.Y}, {"Fill", UDim2.fromOffset(0, 0), Enum.AutomaticSize.XY}, {"Shrink", UDim2.fromOffset(0, 0), Enum.AutomaticSize.XY} } do
	local row = frame({ Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y }, g)
	local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection.Horizontal; l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = row
	frame({ Size = UDim2.fromOffset(40, 40), LayoutOrder = 1 }, row)
	local t = frame({ Size = cfg[2], AutomaticSize = cfg[3], LayoutOrder = 2, Text = "The quick brown fox jumps over the lazy dog and keeps running far away", TextWrapped = true, TextSize = 16, FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json") }, row, "TextLabel")
	local f = Instance.new("UIFlexItem"); f.FlexMode = Enum.UIFlexMode[cfg[1]]; f.Parent = t
	task.wait(); task.wait()
	local got = `{t.AbsoluteSize} {t.TextBounds} {row.AbsoluteSize}`
	if got ~= "260, 32 251, 32 300, 40" then table.insert(failures, `{cfg[1]} {cfg[2]} {cfg[3].Name}: {got}`) end
	row:Destroy()
end
g:Destroy()
assert(#failures == 0, table.concat(failures, "\n"))
return true
]==]

it("wrapped text flexed in horizontal lists reflows at its assigned width", function(own)
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
		client = { name = "FlexedText", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-list-text-reflow" }, function()
		for _, source in { probe, require "./fixtures/ui-wrapped-text-flex" } do
			assert(Lute.chunk.load(source, { environment = runtime.globals })() == true)
		end
		complete = true
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
