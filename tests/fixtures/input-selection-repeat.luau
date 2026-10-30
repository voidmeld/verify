--!strict

return [==[
local run = game:GetService("RunService")
local input = game:GetService("UserInputService")
local gui = game:GetService("GuiService")
local virtual = input:CreateVirtualInput()
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local buttons = {}
for i = 1, 12 do
	local button = Instance.new("TextButton")
	button.Name = "B" .. i
	button.Text = ""
	button.Position = UDim2.fromOffset(100, 24 * (i - 1))
	button.Size = UDim2.fromOffset(100, 20)
	button.Parent = screen
	buttons[i] = button
end
local began, ended = 0, 0
local beginConnection = input.InputBegan:Connect(function(object)
	if object.KeyCode == Enum.KeyCode.Down then began += 1 end
end)
local endConnection = input.InputEnded:Connect(function(object)
	if object.KeyCode == Enum.KeyCode.Down then ended += 1 end
end)
run.RenderStepped:Wait()
gui.SelectedObject = buttons[1]
virtual:SendKey(true, Enum.KeyCode.Down, false)
task.wait(0.2)
assert(gui.SelectedObject == buttons[2], "initial move must precede repeat delay")
task.wait(0.6)
assert(gui.SelectedObject ~= buttons[2], "held direction must repeat")
virtual:SendKey(false, Enum.KeyCode.Down, false)
task.wait(0.1)
local stopped = gui.SelectedObject
task.wait(0.6)
assert(gui.SelectedObject == stopped, "released direction must stop repeating")
assert(began == 1 and ended == 1, "selection repeats must not emit key transitions")
virtual:SendKey(true, Enum.KeyCode.Down, false)
task.wait(2)
assert(gui.SelectedObject == buttons[12], "held navigation must reach the last item without wrapping")
virtual:SendKey(false, Enum.KeyCode.Down, false)
task.wait(0.1)
beginConnection:Disconnect()
endConnection:Disconnect()
gui.SelectedObject = nil
screen:Destroy()
return true
]==]
