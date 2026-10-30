--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local font = Font.new("rbxasset://fonts/families/BuilderSans.json")
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size, params.Width = font, 14, 0
local cases = {
 { "Hi world", 39, 65, false, 65 },
 { "Hi world", 40, 60, true, 65 },
 { "Hi world", 44, 65, true, 65 },
 { "A V", 14, 27, false, 27 },
 { "A V", 15, 22, true, 27 },
 { "T o", 12, 24, false, 24 },
 { "T o", 13, 19, true, 24 },
 { "A  B  C", 28, 54, false, 54 },
 { "A  B  C", 32, 44, true, 54 },
 { "Hi world ", 42, 70, false, 70 },
 { "Hi world ", 45, 65, true, 70 },
 { " Hi world", 42, 70, false, 70 },
 { " Hi world", 45, 65, true, 70 },
 { "one two three", 68, 111, false, 111 },
 { "one two three", 71, 106, true, 111 },
 { "AB", 14, 22, false, 22 },
 { "AB", 15, 22, true, 22 },
}
local scale = 2 / 3
for _, rich in { false, true } do
 for _, height in { 0, 7, 100 } do
 for index, row in cases do
  local label = Instance.new("TextLabel")
  label.FontFace, label.TextSize = font, 14
  label.RichText = rich
  label.Text = if rich then "<u>" .. row[1] .. "</u>" else row[1]
  label.Size, label.Parent = UDim2.fromOffset(row[2], height), screen
  params.Text = row[1]
  local service = game.TextService:GetTextBoundsAsync(params)
  task.wait(0.05)
  assert(math.abs(service.X - row[5] * scale) < 0.00001, "service width " .. index .. ": " .. tostring(service))
  local expectedWidth = (if rich then row[5] else row[3]) * scale
  local expectedFit = if rich then expectedWidth <= row[2] and height >= 14 else row[4]
  assert(math.abs(label.TextBounds.X - expectedWidth) < 0.00001, "GUI width " .. tostring(rich) .. "/" .. index .. ": " .. tostring(label.TextBounds))
  assert(label.TextBounds.Y == 14, "GUI height " .. index)
  assert(label.TextFits == expectedFit, "GUI fit " .. tostring(rich) .. "/" .. height .. "/" .. index)
  label:Destroy()
 end
 end
end
local automatic = Instance.new("TextLabel")
automatic.FontFace, automatic.TextSize = font, 14
automatic.Text = string.rep("Wrapped text ", 6)
automatic.Size, automatic.AutomaticSize = UDim2.fromOffset(100, 0), Enum.AutomaticSize.X
automatic.Parent = screen
task.wait(0.05)
assert(not automatic.TextFits, "automatic width retains its height fit test")
automatic:Destroy()
params:Destroy()
screen:Destroy()
return true
]==]
