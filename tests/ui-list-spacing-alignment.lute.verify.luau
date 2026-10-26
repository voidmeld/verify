--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local g = Instance.new("ScreenGui"); g.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local out = {}
for _, flex in { "SpaceBetween", "SpaceAround", "SpaceEvenly" } do
	for _, align in { "Left", "Center", "Right" } do
		for _, padding in { 0, 10 } do
			local f = Instance.new("Frame"); f.Size = UDim2.fromOffset(400, 50); f.Parent = g
			local l = Instance.new("UIListLayout"); l.FillDirection = Enum.FillDirection.Horizontal; l.HorizontalFlex = Enum.UIFlexAlignment[flex]; l.HorizontalAlignment = Enum.HorizontalAlignment[align]; l.Padding = UDim.new(0, padding); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = f
			local kids = {}
			for i = 1, 3 do local c = Instance.new("Frame"); c.Size = UDim2.fromOffset(60, 20); c.LayoutOrder = i; c.Parent = f; kids[i] = c end
			task.wait(); task.wait()
			local xs = {}
			for _, c in kids do table.insert(xs, string.format("%.2f", c.AbsolutePosition.X - f.AbsolutePosition.X)) end
			table.insert(out, `{flex} {align} pad{padding}: {table.concat(xs, ",")} content={l.AbsoluteContentSize.X}`)
			f:Destroy()
		end
	end
end
g:Destroy()
local rows = { SpaceBetween = "0.00,170.00,340.00", SpaceAround = "36.67,170.00,303.33", SpaceEvenly = "55.00,170.00,285.00" }
local failures = {}
for _, line in out do
	local flex, padding, positions, content = line:match("^(%a+) %a+ pad(%d+): ([%d.,]+) content=(%d+)$")
	if positions ~= rows[flex] or tonumber(content) ~= (if padding == "10" then 200 else 180) then
		table.insert(failures, line)
	end
end
assert(#failures == 0, table.concat(failures, "\n"))
return true
]==]

it("Folder children hit-test in their GuiObject ancestor at the Folder position as Studio 0.744 does", function(own)
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
		client = { name = "Spacing", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-list-spacing-alignment" }, function()
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
