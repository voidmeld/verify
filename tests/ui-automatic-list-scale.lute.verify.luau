--!strict

local Core = require "../src/core"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

local probe = [==[
local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local g = Instance.new("ScreenGui"); g.Parent = pg
local function frame(props, parent) local f = Instance.new("Frame"); for k, v in props do f[k] = v end; f.Parent = parent; return f end
local function list(parent, horizontal, gap)
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or 0)
	l.Parent = parent
end
local function check(name, parent, size, kids)
	task.wait(); task.wait()
	assert(parent.AbsoluteSize == size, name .. " parent " .. tostring(parent.AbsoluteSize))
	for index, expected in kids do
		local child = expected[1]
		assert(child.AbsoluteSize == expected[2], name .. " child " .. index .. " size " .. tostring(child.AbsoluteSize))
		assert(child.AbsolutePosition - parent.AbsolutePosition == expected[3], name .. " child " .. index .. " at " .. tostring(child.AbsolutePosition - parent.AbsolutePosition))
	end
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X }, root)
	list(p, true)
	local a = frame({ Size = UDim2.fromOffset(100, 20) }, p)
	local b = frame({ Size = UDim2.new(0.25, 0, 0, 10) }, p)
	local c = frame({ Size = UDim2.new(0.25, 10, 0, 10) }, p)
	check("two scales", p, Vector2.new(310, 50), { { a, Vector2.new(100, 20), Vector2.new(0, 0) }, { b, Vector2.new(77.5, 10), Vector2.new(100, 0) }, { c, Vector2.new(87.5, 10), Vector2.new(177.5, 0) } })
	root:Destroy()
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X }, root)
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 20); pad.Parent = p
	list(p, true, 5)
	local a = frame({ Size = UDim2.fromOffset(100, 20) }, p)
	local b = frame({ Size = UDim2.new(0.5, 0, 0, 10) }, p)
	check("padding and gap", p, Vector2.new(320, 50), { { a, Vector2.new(100, 20), Vector2.new(10, 0) }, { b, Vector2.new(145, 10), Vector2.new(115, 0) } })
	root:Destroy()
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local mid = frame({ Size = UDim2.fromOffset(200, 100) }, root)
	local p = frame({ Size = UDim2.fromOffset(0, 50), AutomaticSize = Enum.AutomaticSize.X }, mid)
	list(p, true)
	local a = frame({ Size = UDim2.fromOffset(100, 20) }, p)
	local b = frame({ Size = UDim2.new(0.5, 0, 0, 10) }, p)
	check("narrow parent", p, Vector2.new(200, 50), { { a, Vector2.new(100, 20), Vector2.new(0, 0) }, { b, Vector2.new(100, 10), Vector2.new(100, 0) } })
	root:Destroy()
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(60, 50), AutomaticSize = Enum.AutomaticSize.X }, root)
	list(p, true)
	local a = frame({ Size = UDim2.fromOffset(100, 20) }, p)
	local b = frame({ Size = UDim2.new(0.5, 0, 0, 10) }, p)
	check("authored base", p, Vector2.new(300, 50), { { a, Vector2.new(100, 20), Vector2.new(0, 0) }, { b, Vector2.new(150, 10), Vector2.new(100, 0) } })
	root:Destroy()
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(50, 0), AutomaticSize = Enum.AutomaticSize.Y }, root)
	list(p, false)
	local a = frame({ Size = UDim2.fromOffset(20, 100) }, p)
	local b = frame({ Size = UDim2.new(0, 10, 0.5, 0) }, p)
	check("vertical", p, Vector2.new(50, 250), { { a, Vector2.new(20, 100), Vector2.new(0, 0) }, { b, Vector2.new(10, 125), Vector2.new(0, 100) } })
	root:Destroy()
end
do
	local root = frame({ Size = UDim2.fromOffset(400, 300) }, g)
	local p = frame({ Size = UDim2.fromOffset(50, 0), AutomaticSize = Enum.AutomaticSize.Y }, root)
	local a = frame({ Size = UDim2.fromOffset(20, 120) }, p)
	local b = frame({ Size = UDim2.new(0, 10, 0.5, 0), Position = UDim2.fromOffset(25, 0) }, p)
	check("free scale child", p, Vector2.new(50, 120), { { a, Vector2.new(20, 120), Vector2.new(0, 0) }, { b, Vector2.new(10, 60), Vector2.new(25, 0) } })
	root:Destroy()
end
g:Destroy()
return true
]==]

return function(harness: Core.Harness)
	harness:case("scale children size an automatic list parent as Studio 0.744 does", function(check)
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
			client = { name = "AutomaticList", userId = 1, viewport = { x = 800, y = 600 } },
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
		local thread = scheduler.spawnTagged({ context = "client", source = "ui-automatic-list-scale" }, function()
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
