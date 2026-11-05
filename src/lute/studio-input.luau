--!strict

local source = [==[
local function studioInput()
	local keys, buttons = {}, {}
	local function pointAction(point)
		local inset = game:GetService("GuiService"):GetGuiInset()
		return {x = point.X - inset.X, y = point.Y - inset.Y}
	end
	local function sendActions(tool, actions, observed)
		while R:GetAttribute("inputSequence") ~= R:GetAttribute("inputAck") do
			task.wait()
		end
		local sequence = (R:GetAttribute("inputSequence") or 0) + 1
		payload("input", game:GetService("HttpService"):JSONEncode({tool = tool, actions = actions}))
		R:SetAttribute("inputSequence", sequence)
		while R:GetAttribute("inputAck") ~= sequence and not (observed and observed()) do
			task.wait()
		end
	end
	local function send(tool, action, observed)
		sendActions(tool, {action}, observed)
	end
	return {
		PressKey = function(_, code, seconds)
			assert(seconds >= 0 and seconds <= 10, "Studio MCP key press must last between zero and ten seconds")
			sendActions("user_keyboard_input", {
				{action = "keyDown", key_code = code.Name},
				{action = "wait", wait_time_ms = seconds * 1000},
				{action = "keyUp", key_code = code.Name},
			})
		end,
		SendKey = function(_, down, code, repeated)
			assert(not repeated, "Studio MCP does not expose repeated key events")
			local input = game:GetService("UserInputService")
			local delivered = false
			local event = if down then input.InputBegan else input.InputEnded
			local connection = event:Connect(function(value)
				if value.KeyCode == code then delivered = true end
			end)
			send("user_keyboard_input", {action = if down then "keyDown" else "keyUp", key_code = code.Name}, function() return delivered end)
			connection:Disconnect()
			keys[code.Name] = if down then true else nil
		end,
		SendTextInput = function(_, text)
			send("user_keyboard_input", {action = "textInput", text_inputs = text})
		end,
		SendMousePosition = function(_, point)
			local action = pointAction(point)
			action.action = "moveTo"
			send("user_mouse_input", action)
		end,
		SendMouseButton = function(_, point, button, down, count)
			assert(count == 0, "Studio MCP does not expose mouse repeat counts")
			assert(button == Enum.UserInputType.MouseButton1 or button == Enum.UserInputType.MouseButton2, "Studio MCP requires a left or right mouse button")
			local action = pointAction(point)
			action.action = if down then "mouseButtonDown" else "mouseButtonUp"
			action.mouse_button = if button == Enum.UserInputType.MouseButton1 then "left" else "right"
			send("user_mouse_input", action)
			buttons[button.Name] = if down then action else nil
		end,
		close = function()
			for code in keys do
				send("user_keyboard_input", {action = "keyUp", key_code = code})
			end
			for _, action in buttons do
				action.action = "mouseButtonUp"
				send("user_mouse_input", action)
			end
			table.clear(keys)
			table.clear(buttons)
		end,
	}
end
]==]

return { source = source }
