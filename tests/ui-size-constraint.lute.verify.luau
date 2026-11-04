--!strict

local Test = require "./harness"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local probe = require "./fixtures/ui-size-constraint"

Test.it("size constraints choose the parent axis and preserve position, scale and limits", function(own)
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
		client = { name = "Layout", userId = 1, viewport = { x = 800, y = 600 } },
		beforeRender = assert(bridge.layout).step,
	})
	own(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	table.insert(roots, assert(assert(runtime.localPlayer):FindFirstChild "PlayerGui"))
	local complete = false
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-size-constraint" }, function()
		complete = Lute.chunk.load(probe, { environment = runtime.globals })() == true
	end)
	own(function()
		scheduler.cancel(thread)
	end)
	for _ = 1, 120 do
		if complete or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	Test.expect(scheduler.failures):toEqual {}
	Test.expect(engine.diagnostics):toEqual {}
	Test.expect(complete):toBe(true)
end)

Test.it("cross-axis relative children under automatic parents refuse before publication", function(own)
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
	local env = bridge.environment
	local parent = env.createInstance "Frame"
	parent.Size, parent.AutomaticSize =
		Roblox.datatypes.UDim2.fromOffset(100, 100), Roblox.datatypes.Enum.AutomaticSize.XY
	local child = env.createInstance "Frame"
	child.SizeConstraint, child.Size, child.Parent =
		Roblox.datatypes.Enum.SizeConstraint.RelativeXX, Roblox.datatypes.UDim2.fromScale(0.5, 0.5), parent
	table.insert(roots, parent)
	Test.expect(function()
		assert(bridge.layout).step()
	end):toThrow "SizeConstraint under automatic size"
	Test.expect(env.propertyOf(parent, "AbsoluteSize")):toBe(Roblox.datatypes.Vector2.zero)
	Test.expect(env.propertyOf(child, "AbsoluteSize")):toBe(Roblox.datatypes.Vector2.zero)
end)

return nil
