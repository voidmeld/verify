--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local function frame(props, parent) local f = Instance.new("Frame"); for k, v in props do f[k] = v end; f.Parent = parent; return f end
local function case(name, mode, bProps, parentSize, childSize, childAt)
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize[mode] }, root)
	frame({ Size = UDim2.fromOffset(100, 20) }, p)
	local b = frame(bProps, p)
	task.wait(); task.wait()
	assert(p.AbsoluteSize == parentSize, name .. " parent " .. tostring(p.AbsoluteSize))
	assert(b.AbsoluteSize == childSize, name .. " child size " .. tostring(b.AbsoluteSize))
	assert(b.AbsolutePosition - p.AbsolutePosition == childAt, name .. " child at " .. tostring(b.AbsolutePosition - p.AbsolutePosition))
	root:Destroy()
end
case("offset x, centred y", "XY", { Size = UDim2.fromOffset(40, 10), Position = UDim2.new(0, 150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) }, Vector2.new(190, 20), Vector2.new(40, 10), Vector2.new(150, 5))
case("trailing outside", "XY", { Size = UDim2.fromOffset(40, 10), Position = UDim2.new(1, 8, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) }, Vector2.new(148, 20), Vector2.new(40, 10), Vector2.new(108, 5))
case("leading outside", "XY", { Size = UDim2.fromOffset(40, 10), Position = UDim2.new(0, -30, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) }, Vector2.new(100, 20), Vector2.new(40, 10), Vector2.new(-30, 5))
case("tall centred", "XY", { Size = UDim2.fromOffset(40, 60), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) }, Vector2.new(100, 45), Vector2.new(40, 60), Vector2.new(0, -15))
case("width only", "X", { Size = UDim2.fromOffset(40, 10), Position = UDim2.new(0, 150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) }, Vector2.new(190, 0), Vector2.new(40, 10), Vector2.new(150, -5))
case("offset below", "XY", { Size = UDim2.fromOffset(40, 10), Position = UDim2.new(0, 150, 0, 30) }, Vector2.new(190, 40), Vector2.new(40, 10), Vector2.new(150, 30))
g:Destroy()
return true
]==]

return function(harness: Core.Harness)
	harness:case("positioned children grow an automatic parent as Studio 0.744 does", function(check)
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
		check:defer(function()
			bridge.close()
		end)
		local engine = bridge.placeEngine()
		local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
			aliases = {},
			cache = Roblox.createPlaceCache(Lute.fixture.host),
			host = Lute.fixture.host,
			client = { name = "AutomaticFree", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		check:defer(function()
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
		check:defer(input.close)
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-automatic-free-children" }, function()
			complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
		end)
		check:defer(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 240 do
			if complete or #scheduler.failures > 0 then
				break
			end
			runtime.step(1 / 60)
		end
		check:expect(scheduler.failures):toEqual {}
		check:expect(engine.diagnostics):toEqual {}
		check:expect(complete):toBe(true)
	end)
end
