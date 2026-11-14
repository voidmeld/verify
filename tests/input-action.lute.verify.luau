--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

it("a scriptable input binding feeds its action and refuses other binding types", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local env = bridge.environment
	local action = env.createInstance "InputAction"
	action.Parent = bridge.placeEngine().game
	local scripted = env.createInstance "InputBinding"
	scripted.Type = Roblox.datatypes.Enum.InputBindingType.Scriptable
	scripted.Parent = action
	local automatic = env.createInstance "InputBinding"
	automatic.Parent = action
	local state = env.method(action, "GetState")
	env.method(scripted, "Fire")(scripted, true)
	expect(state(action)):toBe(true)
	expect(function()
		env.method(scripted, "Fire")(scripted, 1)
	end):toThrow()
	expect(function()
		env.method(automatic, "Fire")(automatic, false)
	end):toThrow()
	action.Enabled = false
	env.method(scripted, "Fire")(scripted, false)
	expect(state(action)):toBe(false)
end)

it("scripted input actions retain state and suppress duplicate transitions", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local env = bridge.environment
	local action = env.createInstance "InputAction"
	action.Parent = bridge.placeEngine().game
	local fire = env.method(action, "Fire")
	local state = env.method(action, "GetState")
	local events: { string } = {}
	for _, name in { "Pressed", "Released", "StateChanged" } do
		local signal = env.event(action, name)
		signal:Connect(function()
			local current = state(action)
			table.insert(events, name .. ":" .. tostring(current))
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
	own(function()
		bridge.close()
	end)
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
		local fire = env.method(action, "Fire")
		local state = env.method(action, "GetState")
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
	own(function()
		bridge.close()
	end)
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

it("reparenting a container resets its pressed actions and ignores destroyed ones", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local env = bridge.environment
	local root = bridge.placeEngine().game
	local folder = env.createInstance "Folder"
	folder.Parent = root
	local pressed = env.createInstance "InputAction"
	pressed.Parent = folder
	local destroyed = env.createInstance "InputAction"
	destroyed.Parent = folder
	local state = env.method(pressed, "GetState")
	local fire = env.method(pressed, "Fire")
	expect(state(pressed)):toBe(false)
	fire(pressed, true)
	expect(state(pressed)):toBe(true)
	local released = 0
	env.event(destroyed, "Released"):Connect(function()
		released += 1
	end)
	env.method(destroyed, "Fire")(destroyed, true)
	local destroy = env.method(destroyed, "Destroy")
	destroy(destroyed)
	env.step(0)
	local settled = released
	folder.Parent = nil
	env.step(0)
	expect(state(pressed)):toBe(false)
	expect(released):toBe(settled)
end)

it("reparenting a container leaves actions outside it pressed", function(own)
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	local env = bridge.environment
	local root = bridge.placeEngine().game
	local inside = env.createInstance "Folder"
	inside.Parent = root
	local outside = env.createInstance "Folder"
	outside.Parent = root
	local held = env.createInstance "InputAction"
	held.Parent = inside
	local bystander = env.createInstance "InputAction"
	bystander.Parent = outside
	local nested = env.createInstance "Folder"
	nested.Parent = inside
	local deep = env.createInstance "InputAction"
	deep.Parent = nested
	for _, action in { held, bystander, deep } do
		env.method(action, "Fire")(action, true)
	end
	inside.Parent = nil
	env.step(0)
	expect(env.method(held, "GetState")(held)):toBe(false)
	expect(env.method(deep, "GetState")(deep)):toBe(false)
	expect(env.method(bystander, "GetState")(bystander)):toBe(true)
end)

it("preferred bindings follow the input device and binding reparenting", function(own)
	local bridge = Lute.fixture.bridge()
	own(bridge.close)
	local env, engine = bridge.environment, bridge.placeEngine()
	local library = engine.datatypes
	local service = engine.service "UserInputService"
	env.poke(service, "PreferredInput", library.Enum.PreferredInput.KeyboardAndMouse)
	local container = env.createInstance "Folder"
	local action = env.createInstance("InputAction", { Parent = container })
	local keyboard = env.createInstance("InputBinding", { KeyCode = library.Enum.KeyCode.K, Parent = action })
	local gamepad = env.createInstance("InputBinding", { KeyCode = library.Enum.KeyCode.ButtonX, Parent = action })
	local touch = env.createInstance("InputBinding", { UIButton = env.createInstance "TextButton", Parent = action })
	container.Parent = engine.game
	expect(action.PreferredBinding):toBe(keyboard)
	local changed = 0
	own(function()
		container:Destroy()
	end)
	local connection = action:GetPropertyChangedSignal("PreferredBinding"):Connect(function()
		changed += 1
	end)
	own(function()
		connection:Disconnect()
	end)
	env.poke(service, "PreferredInput", library.Enum.PreferredInput.Gamepad)
	expect(action.PreferredBinding):toBe(gamepad)
	keyboard.DisplayName = "Keyboard"
	local field = env.createInstance("TextBox", { Parent = container })
	for _, text in { "t", "ty", "typ", "type" } do
		field.Text = text
	end
	expect(action.PreferredBinding):toBe(gamepad)
	expect(changed):toBe(1)
	gamepad.Parent = nil
	expect(action.PreferredBinding):toBe(nil)
	gamepad.Parent = action
	expect(action.PreferredBinding):toBe(gamepad)
	env.poke(service, "PreferredInput", library.Enum.PreferredInput.Touch)
	expect(action.PreferredBinding):toBe(touch)
	local button = touch.UIButton
	touch.UIButton = nil
	expect(action.PreferredBinding):toBe(nil)
	touch.UIButton = button
	expect(action.PreferredBinding):toBe(touch)
	touch:Destroy()
	expect(action.PreferredBinding):toBe(nil)
	env.poke(service, "PreferredInput", library.Enum.PreferredInput.KeyboardAndMouse)
	expect(action.PreferredBinding):toBe(keyboard)
	keyboard.KeyCode = library.Enum.KeyCode.ButtonY
	expect(action.PreferredBinding):toBe(nil)
end)

return nil
