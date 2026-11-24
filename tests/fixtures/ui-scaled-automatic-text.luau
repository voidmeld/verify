--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
for _, automatic in { "X", "Y", "XY" } do
 for _, size in { Vector2.new(40, 40), Vector2.new(0, 40), Vector2.new(40, 0), Vector2.new(0, 0) } do
  if automatic == "X" and size.Y == 0 or automatic == "Y" and size.X == 0 then continue end
  local label = Instance.new("TextLabel")
  label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
  label.Text, label.TextSize, label.TextScaled = "AB", 14, true
  label.Size, label.AutomaticSize = UDim2.fromOffset(size.X, size.Y), Enum.AutomaticSize[automatic]
  label.Parent = screen
  task.wait(.1)
  assert(label.TextFits, `{automatic} {size}: text fits`)
  assert(label.AbsoluteSize.X >= size.X and label.AbsoluteSize.Y >= size.Y, `{automatic} {size}: authored minimum`)
  if automatic == "X" then
   assert(label.AbsoluteSize.Y == size.Y and label.TextBounds.Y == size.Y, `automatic X {size}: {label.TextBounds}`)
   assert(label.AbsoluteSize.X == math.max(size.X, label.TextBounds.X), `automatic X width {size}`)
  elseif automatic == "Y" then
   assert(label.AbsoluteSize.X == size.X and label.TextBounds.X <= size.X, `automatic Y width {size}`)
   assert(label.AbsoluteSize.Y == math.max(size.Y, label.TextBounds.Y), `automatic Y height {size}`)
  else
   assert(label.TextBounds.Y == 100 and label.AbsoluteSize.Y == 100, `automatic XY height {size}`)
   assert(label.AbsoluteSize.X == label.TextBounds.X, `automatic XY width {size}`)
  end
  local constraint = Instance.new("UITextSizeConstraint")
  constraint.MaxTextSize, constraint.Parent = 16, label
  label.Size = UDim2.fromScale(1, 1)
  label.AutomaticSize = Enum.AutomaticSize.XY
  task.wait(.1)
  assert(label.TextBounds.Y == 16 and label.TextFits, "relative automatic avatar respects its constraint")
  label.Text = "WW"
  task.wait(.1)
  assert(label.TextBounds.Y == 16 and label.TextFits, "automatic avatar remeasures changed initials")
  label:Destroy()
 end
end
screen:Destroy()
return true
]==]
