--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui"); screen.Parent = playerGui
local turned = Instance.new("Frame"); turned.Position = UDim2.fromOffset(100, 100); turned.Size = UDim2.fromOffset(100, 20); turned.Rotation = 90; turned.Parent = screen
local child = Instance.new("Frame"); child.Position = UDim2.fromOffset(10, 5); child.Size = UDim2.fromOffset(20, 10); child.Parent = turned
local row = Instance.new("Frame"); row.Position = UDim2.fromOffset(300, 300); row.Size = UDim2.fromOffset(200, 50); row.Parent = screen
local list = Instance.new("UIListLayout"); list.FillDirection = Enum.FillDirection.Horizontal; list.Parent = row
local first = Instance.new("Frame"); first.Size = UDim2.fromOffset(40, 40); first.Rotation = 45; first.Parent = row
local second = Instance.new("Frame"); second.Size = UDim2.fromOffset(40, 40); second.Parent = row
task.wait(); task.wait()
assert(turned.AbsolutePosition == Vector2.new(100, 100) and turned.AbsoluteSize == Vector2.new(100, 20), "rotation keeps the rotated layout box")
assert(turned.AbsoluteRotation == 90, "rotated absolute rotation")
assert(child.AbsolutePosition == Vector2.new(140, 75) and child.AbsoluteSize == Vector2.new(20, 10), "child center turns around the parent center " .. tostring(child.AbsolutePosition))
assert(child.AbsoluteRotation == 90, "child inherits rotation")
assert(first.AbsolutePosition == Vector2.new(300, 300) and second.AbsolutePosition == Vector2.new(340, 300), "list layout ignores rotation")
local center = turned.AbsolutePosition + turned.AbsoluteSize / 2
local function hit(x, y) return table.find(playerGui:GetGuiObjectsAtPosition(x, y), turned) ~= nil end
assert(not hit(turned.AbsolutePosition.X + 95, turned.AbsolutePosition.Y + 2), "the unrotated corner misses")
assert(hit(center.X, center.Y + 45), "the rotated extent hits")
screen:Destroy()
return true
]==]

it("rotation turns descendants and hit tests as Studio 0.744 does", function(own)
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
		client = { name = "Rotation", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-rotation" }, function()
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
