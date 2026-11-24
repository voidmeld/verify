--!strict

local Environment = require "./environment-types"
local D = require "./datatypes"

export type Options = {
	preferredInput: D.EnumMember,
	touch: boolean,
	keyboard: boolean,
	mouse: boolean,
	gamepad: boolean,
	topLeft: D.Vector2Value,
	bottomRight: D.Vector2Value,
	topbar: D.RectValue,
}

type Engine = { environment: Environment.Environment, service: (string) -> Environment.Instance }

local function configure(engine: Engine, options: Options)
	local environment = engine.environment
	local input, gui = engine.service "UserInputService", engine.service "GuiService"
	assert(
		D.typeName(options.preferredInput) == "EnumItem" and D.enumType(options.preferredInput) == "PreferredInput",
		"device requires Enum.PreferredInput"
	)
	assert(
		type(options.touch) == "boolean"
			and type(options.keyboard) == "boolean"
			and type(options.mouse) == "boolean"
			and type(options.gamepad) == "boolean",
		"device capabilities must be boolean"
	)
	for _, value in { options.topLeft, options.bottomRight } do
		assert(D.typeName(value) == "Vector2", "device inset requires Vector2")
		assert(
			value.X >= 0 and value.Y >= 0 and value.X < math.huge and value.Y < math.huge,
			"device insets must be finite and nonnegative"
		)
	end
	assert(D.typeName(options.topbar) == "Rect", "device topbar requires Rect")
	for _, value in { options.topbar.Min.X, options.topbar.Min.Y, options.topbar.Max.X, options.topbar.Max.Y } do
		assert(value == value and math.abs(value) < math.huge, "device topbar must be finite")
	end
	local preferred = options.preferredInput.Name
	assert(
		(preferred ~= "Touch" or options.touch)
			and (preferred ~= "Gamepad" or options.gamepad)
			and (preferred ~= "KeyboardAndMouse" or options.keyboard or options.mouse),
		"preferred input requires an enabled device"
	)
	local topLeft, bottomRight = options.topLeft, options.bottomRight
	environment.fake("GuiService.GetGuiInset", function(): (D.Vector2Value, D.Vector2Value)
		return topLeft, bottomRight
	end)
	environment.publish(gui, "TopbarInset", options.topbar)
	environment.publish(input, "TouchEnabled", options.touch)
	environment.publish(input, "KeyboardEnabled", options.keyboard)
	environment.publish(input, "MouseEnabled", options.mouse)
	environment.publish(input, "GamepadEnabled", options.gamepad)
	environment.publish(input, "PreferredInput", options.preferredInput)
	for _, name in { "GetKeysPressed", "GetMouseButtonsPressed" } do
		environment.fake("UserInputService." .. name, function(): { unknown }
			return {}
		end)
	end
	for _, name in { "IsKeyDown", "IsMouseButtonPressed", "IsGamepadButtonDown" } do
		environment.fake("UserInputService." .. name, function(): boolean
			return false
		end)
	end
end

return { configure = configure }
