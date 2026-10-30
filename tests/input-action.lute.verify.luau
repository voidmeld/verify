--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

type Instance = Roblox.Instance
type Fire = (Instance, unknown) -> ()
type GetState = (Instance) -> unknown

it("scripted input actions retain state and suppress duplicate transitions", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local env = bridge.environment
	local action = env.createInstance "InputAction"
	action.Parent = bridge.placeEngine().game
	local fire = action.Fire :: Fire
	local state = action.GetState :: GetState
	local events: { string } = {}
	for _, name in { "Pressed", "Released", "StateChanged" } do
		local signal = action[name] :: Roblox.Signal<...unknown>
		signal:Connect(function()
			table.insert(events, name .. ":" .. tostring(state(action)))
		end)
	end
	expect(state(action)):toBe(false)
	action.Enabled = false
	fire(action, true)
	expect(state(action)):toBe(false)
	action.Enabled = true
	fire(action, false)
	fire(action, true)
	fire(action, true)
	fire(action, false)
	fire(action, false)
	expect(events):toEqual { "Pressed:true", "StateChanged:true", "Released:false", "StateChanged:false" }
	expect(function()
		fire(action, 1)
	end):toThrow()
	expect(state(action)):toBe(false)
end)

it("directional input actions validate their state and emit no button events", function(own)
	local snapshot = Lute.fixture.load()
	local library = Roblox.reflectionSnapshot.library(snapshot)
	local bridge = Lute.fixture.bridge(snapshot)
	own(bridge.close)
	local env = bridge.environment
	local entries: { { kind: string, zero: unknown, value: unknown } } = {
		{ kind = "Direction1D", zero = 0, value = 0.5 },
		{ kind = "Direction2D", zero = library.Vector2.zero, value = library.Vector2.new(0.5, -0.5) },
		{ kind = "Direction3D", zero = library.Vector3.zero, value = library.Vector3.new(0.5, -0.5, 0.25) },
	}
	for _, entry in entries do
		local action = env.createInstance "InputAction"
		action.Type = library.Enum.InputActionType[entry.kind]
		action.Parent = bridge.placeEngine().game
		local fire = action.Fire :: Fire
		local state = action.GetState :: GetState
		expect(state(action)):toEqual(entry.zero)
		fire(action, entry.value)
		fire(action, entry.value)
		expect(state(action)):toEqual(entry.value)
		expect(env.signalOf(action, "StateChanged").fires()):toBe(2)
		expect(env.signalOf(action, "Pressed").fires()):toBe(0)
		expect(env.signalOf(action, "Released").fires()):toBe(0)
		expect(function()
			fire(action, true)
		end):toThrow()
		expect(state(action)):toEqual(entry.value)
	end
end)

it("input action lifecycle matches the shared Studio sequence", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local engine = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
		client = { name = "Actions", userId = 1, viewport = { x = 800, y = 600 } },
	})
	own(function()
		for index = #runtime.closeHandlers, 1, -1 do
			runtime.closeHandlers[index]()
		end
	end)
	local result: unknown = nil
	local scheduler = bridge.environment.scheduler
	local thread = scheduler.spawnTagged({ context = "client", source = "input-action-probe" }, function()
		result = Lute.chunk.load(require "./fixtures/input-action-probe", { environment = runtime.globals })()
	end)
	own(function()
		scheduler.cancel(thread)
	end)
	for _ = 1, 120 do
		if result ~= nil or #scheduler.failures > 0 then
			break
		end
		runtime.step(1 / 60)
	end
	expect(scheduler.failures):toEqual {}
	expect(result):toBe(true)
end)

return nil
