--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local expect, it = Test.expect, Test.it

it("device presets publish input capabilities and camera screen insets", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env, types = engine.environment, engine.datatypes
	local input, gui = engine.service "UserInputService", engine.service "GuiService"
	local camera = engine.newInstance "Camera"
	camera.CFrame = types.CFrame.identity
	env.poke(camera, "ViewportSize", types.Vector2.new(800, 600))
	camera.Parent = engine.service "Workspace"
	local options = {
		preferredInput = types.Enum.PreferredInput.Touch,
		touch = true,
		keyboard = false,
		mouse = false,
		gamepad = false,
		topLeft = types.Vector2.new(0, 58),
		bottomRight = types.Vector2.new(0, 12),
		topbar = types.Rect.new(100, 0, 800, 58),
	}
	local changes = 0
	input:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		changes += 1
	end)
	local action = engine.newInstance "InputAction"
	local keyboard = engine.newInstance "InputBinding"
	keyboard.KeyCode, keyboard.Parent = types.Enum.KeyCode.K, action
	local touch = engine.newInstance "InputBinding"
	touch.UIButton, touch.Parent = engine.newInstance "TextButton", action
	action.Parent = engine.game
	Roblox.deviceFakes.configure(engine, options)
	expect(action.PreferredBinding):toBe(touch)
	expect(input.PreferredInput):toBe(types.Enum.PreferredInput.Touch)
	expect(input.TouchEnabled):toBe(true)
	expect(input.KeyboardEnabled):toBe(false)
	expect(gui.TopbarInset):toBe(options.topbar)
	local topLeft, bottomRight = env.method(gui, "GetGuiInset")(gui)
	expect(topLeft):toBe(options.topLeft)
	expect(bottomRight):toBe(options.bottomRight)
	for _, name in { "GetKeysPressed", "GetMouseButtonsPressed" } do
		expect(env.method(input, name)(input)):toEqual {}
	end
	for _, name in { "IsKeyDown", "IsMouseButtonPressed", "IsGamepadButtonDown" } do
		expect(env.method(input, name)(input)):toBe(false)
	end
	local project = env.method(camera, "WorldToScreenPoint")
	local point = project(camera, types.Vector3.new(0, 0, -10))
	expect(point):toBe(types.Vector3.new(400, 242, 10))
	options.touch, options.keyboard = false, true
	options.preferredInput = types.Enum.PreferredInput.KeyboardAndMouse
	Roblox.deviceFakes.configure(engine, options)
	expect(changes):toBe(2)
	expect(action.PreferredBinding):toBe(keyboard)
end)

it("device validation rejects invalid presets before publishing state", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env, types = engine.environment, engine.datatypes
	local input, gui = engine.service "UserInputService", engine.service "GuiService"
	local options = {
		preferredInput = types.Enum.PreferredInput.KeyboardAndMouse,
		touch = false,
		keyboard = true,
		mouse = true,
		gamepad = false,
		topLeft = types.Vector2.zero,
		bottomRight = types.Vector2.zero,
		topbar = types.Rect.new(0, 0, 800, 0),
	}
	Roblox.deviceFakes.configure(engine, options)
	options.preferredInput = types.Enum.PreferredInput.Touch
	expect(pcall(Roblox.deviceFakes.configure, engine, options)):toBe(false)
	expect(input.PreferredInput):toBe(types.Enum.PreferredInput.KeyboardAndMouse)
	options.touch = true
	options.topLeft = types.Vector2.new(0, -1)
	expect(pcall(Roblox.deviceFakes.configure, engine, options)):toBe(false)
	expect(env.method(gui, "GetGuiInset")(gui)):toBe(types.Vector2.zero)
	options.topLeft = types.Vector2.zero
	options.preferredInput = types.Enum.KeyCode.Space
	expect(pcall(Roblox.deviceFakes.configure, engine, options)):toBe(false)
end)

return nil
