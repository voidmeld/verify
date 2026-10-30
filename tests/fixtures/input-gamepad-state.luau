--!strict

return [==[
local input = game:GetService("UserInputService")
for _, gamepad in {Enum.UserInputType.Gamepad1, Enum.UserInputType.Gamepad8} do
	local states = input:GetGamepadState(gamepad)
	assert(#states == 24, "gamepads expose 24 initial controls, got " .. #states)
	local seen = {}
	for _, state in states do
		assert(state.UserInputType == gamepad, "gamepad state retains device identity")
		assert(state.UserInputState == Enum.UserInputState.End, "idle control state")
		assert(state.Position == Vector3.zero, "idle control position")
		assert(not seen[state.KeyCode], "control appears only once")
		seen[state.KeyCode] = true
	end
	for _, code in {Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonB, Enum.KeyCode.DPadDown, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2} do
		assert(seen[code], "gamepad has buttons, directional pad and thumbsticks")
	end
	table.clear(states)
	assert(#input:GetGamepadState(gamepad) == 24, "returned arrays do not own the device state")
end
assert(#input:GetGamepadState(Enum.UserInputType.Keyboard) == 0, "non-gamepad input has no gamepad controls")
return true
]==]
