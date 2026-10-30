--!strict
local Test = require "./harness"
local Roblox = require "../src/roblox"
local Lute = require "../src/lute"

for _, case in
	{
		{
			name = "touch contact events and button activation match native input",
			source = require "./fixtures/input-touch-button",
		},
		{ name = "touch drag capture matches native input", source = require "./fixtures/input-touch-drag" },
	}
do
	Test.it(case.name, function(own)
		local roots: { Roblox.Instance } = {}
		local placed: Roblox.PlaceRuntime? = nil
		local bridge = Lute.fixture.bridge(nil, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					local viewport = assert(placed).device().viewport
					return { X = viewport[1], Y = viewport[2] }
				end,
				screenArea = function(screen)
					return assert(placed).screenArea(screen)
				end,
			},
		})
		own(bridge.close)
		local engine = bridge.placeEngine()
		local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
			aliases = {},
			cache = Roblox.createPlaceCache(Lute.fixture.host),
			host = Lute.fixture.host,
			client = { name = "Touch", userId = 1, viewport = { x = 800, y = 600 } },
			beforeRender = assert(bridge.layout).step,
		})
		placed = runtime
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
				local inset = runtime.device().guiInset
				return { X = inset[1], Y = inset[2] }
			end,
			library = (engine.datatypes :: unknown) :: Roblox.DatatypeLibrary,
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		own(input.close)
		local complete = false
		local scheduler = bridge.environment.scheduler
		local thread = scheduler.spawnTagged({ context = "client", source = "input-touch" }, function()
			complete = Lute.chunk.load(case.source, { environment = runtime.globals })() == true
		end)
		own(function()
			scheduler.cancel(thread)
		end)
		for _ = 1, 1200 do
			if complete or #scheduler.failures > 0 then
				break
			end
			runtime.step(1 / 60)
		end
		Test.expect(scheduler.failures):toEqual {}
		Test.expect(engine.diagnostics):toEqual {}
		Test.expect(complete):toBe(true)
	end)
end

return nil
