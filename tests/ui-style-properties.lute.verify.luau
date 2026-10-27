--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Roblox = require "../src/roblox"
local Lute = require "../src/lute"
local probe = require "./fixtures/ui-style-properties"

it("style property resolution matches the same native conformance assertions", function(own)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		ui = { measureBounds = false, measureText = false },
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
		client = { name = "Grid", userId = 1, viewport = { x = 800, y = 600 } },
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
	local thread = scheduler.spawnTagged({ context = "client", source = "ui-style-properties" }, function()
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
	expect(engine.diagnostics):toEqual {}
	expect(complete):toBe(true)
end)

it("updates a populated unstyled screen after layout within its interaction budget", function(own)
	local roots: { Roblox.Instance } = {}
	local bridge = Lute.fixture.bridge(nil, {
		ui = { measureBounds = false, measureText = false },
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
	local screen = engine.newInstance "ScreenGui"
	table.insert(roots, screen)
	local panels: { Roblox.Instance } = {}
	for index = 1, 256 do
		local panel = engine.newInstance "Frame"
		panel.Size = engine.datatypes.UDim2.fromOffset(40, 40)
		panel.Parent = screen
		panels[index] = panel
	end
	assert(bridge.layout).step()
	local started = os.clock()
	for index, panel in panels do
		panel.Position = engine.datatypes.UDim2.fromOffset(index, index)
		expect(os.clock() - started < 5):toBe(true)
	end
	assert(bridge.layout).step()
	expect(panels[256].AbsolutePosition.X):toBe(256)
end)

return nil
