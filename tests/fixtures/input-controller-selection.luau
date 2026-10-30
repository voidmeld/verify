--!strict

return [==[
local input, gui = game.UserInputService, game.GuiService
local virtual = input:CreateVirtualInput()
assert(input.PreferredInput == Enum.PreferredInput.Gamepad, "controller emulator prefers gamepad input")
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local buttons, connections, trace = {}, {}, {}
local function selection() return if gui.SelectedObject then gui.SelectedObject.Name else "none" end
for index = 1, 4 do
 local button = Instance.new("TextButton")
 button.Name, button.Text = "B" .. index, ""
 button.Size, button.Position = UDim2.fromOffset(100, 30), UDim2.fromOffset(100, 100 + 40 * index)
 button.Parent, buttons[index] = screen, button
 table.insert(connections, button.Activated:Connect(function(object, count)
  table.insert(trace, "Activated/" .. button.Name .. "/" .. object.KeyCode.Name .. "/" .. count)
 end))
end
for _, event in {"InputBegan", "InputChanged", "InputEnded"} do
 table.insert(connections, input[event]:Connect(function(object, processed)
  if object.UserInputType == Enum.UserInputType.Gamepad1 then
   table.insert(trace, event .. "/" .. object.KeyCode.Name .. "/" .. tostring(processed) .. "/" .. selection())
  end
 end))
end
task.wait(0.2)
gui.SelectedObject = buttons[1]
virtual:SendKey(true, Enum.KeyCode.Nine, false)
task.wait(0.1)
assert(#trace == 1, "ButtonA does not activate on press")
virtual:SendKey(false, Enum.KeyCode.Nine, false)
task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.Three, false)
task.wait(0.2)
assert(gui.SelectedObject == buttons[2], "DPad moves once before repeat delay")
task.wait(0.7)
assert(gui.SelectedObject == buttons[4], "held DPad moves through the list")
virtual:SendKey(false, Enum.KeyCode.Three, false)
task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.Zero, false)
task.wait(0.1)
virtual:SendKey(false, Enum.KeyCode.Zero, false)
task.wait(0.1)
assert(gui.SelectedObject == buttons[4], "ButtonB leaves selection unchanged")
virtual:SendKey(true, Enum.KeyCode.W, false)
task.wait(0.8)
assert(gui.SelectedObject == buttons[3], "held left stick moves once")
virtual:SendKey(false, Enum.KeyCode.W, false)
task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.W, false)
task.wait(0.1)
assert(gui.SelectedObject == buttons[2], "left stick moves again after release")
virtual:SendKey(false, Enum.KeyCode.W, false)
task.wait(0.1)
virtual:SendKey(true, Enum.KeyCode.I, false)
task.wait(0.1)
virtual:SendKey(false, Enum.KeyCode.I, false)
task.wait(0.1)
assert(gui.SelectedObject == buttons[2], "right stick does not change selection")
local expected = {
 "InputBegan/ButtonA/true/B1",
 "Activated/B1/ButtonA/1",
 "InputEnded/ButtonA/true/B1",
 "InputBegan/DPadDown/true/B2",
 "InputEnded/DPadDown/true/B4",
 "InputBegan/ButtonB/false/B4",
 "InputEnded/ButtonB/false/B4",
 "InputChanged/Thumbstick1/true/B3",
 "InputEnded/Thumbstick1/true/B3",
 "InputChanged/Thumbstick1/true/B2",
 "InputEnded/Thumbstick1/true/B2",
 "InputChanged/Thumbstick2/false/B2",
 "InputEnded/Thumbstick2/false/B2",
}
gui.SelectedObject = nil
for _, connection in connections do connection:Disconnect() end
screen:Destroy()
assert(table.concat(trace, "|") == table.concat(expected, "|"), table.concat(trace, "|"))
return true
]==]
