--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local font = Font.new("rbxasset://fonts/families/BuilderSans.json")
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Text, params.Size, params.Width = font, "A", 14, 0
game.TextService:GetTextBoundsAsync(params)
params:Destroy()
local function near(a, b) return math.abs(a - b) <= 0.001 end
local function observe(text, wrapped, spacing, height, alignment)
 local label = Instance.new("TextLabel")
 label.FontFace = font
 label.Text, label.TextWrapped, label.TextSize = text, wrapped, 14
 label.TextYAlignment, label.LineHeight = Enum.TextYAlignment[alignment], spacing
 label.Size, label.Parent = UDim2.fromOffset(40, height), screen
 task.wait(0.05)
 local bounds, fits = label.TextBounds, label.TextFits
 label:Destroy()
 return bounds, fits
end
local line = observe("Hi world", false, 1, 100, "Top").Y
for _, text in {"Hi\nworld", "Hi world"} do
 for _, spacing in {1, 1.2, 2} do
  for _, wrapped in {false, true} do
   local tall = observe(text, wrapped, spacing, 1000, "Top")
   local lines = math.floor((tall.Y / line - 1) / spacing + 1.5)
   assert(lines >= 1 and near(tall.Y, line * (1 + (lines - 1) * spacing)), "full height is whole line steps")
   assert((lines >= 2) == (wrapped or text ~= "Hi world"), "the sample text spans the expected lines")
   local previous = 0
   for _, height in {0, 14, 20, 28, 40, 100} do
    if not wrapped and text ~= "Hi world" and height < tall.Y then continue end
    local reference = nil
    for _, alignment in {"Top", "Center", "Bottom"} do
     local tag = text .. "/" .. spacing .. "/" .. tostring(wrapped) .. "/" .. height .. "/" .. alignment
     local bounds, fits = observe(text, wrapped, spacing, height, alignment)
     local visible = math.min(lines, math.max(1, math.floor((height / line - 1) / spacing + 1 + 0.0001)))
     if not wrapped and text == "Hi world" then
      assert(near(bounds.Y, line) and (fits or bounds.X > 40.001 or height < line), "a single unwrapped line that is narrow enough fits a tall enough label " .. tag)
     else
      assert(near(bounds.Y, line * (1 + (visible - 1) * spacing)), "height clamps to whole line steps " .. tag .. ": " .. tostring(bounds))
      assert(fits == (visible == lines), "fit means every line is visible " .. tag)
     end
     assert(bounds.X > 0 and (not wrapped or bounds.X <= 41.01), "wrapped width stays within the label " .. tag)
     assert(bounds.Y >= previous - 0.001 or alignment ~= "Top", "visible height grows with the label " .. tag)
     if reference then
      assert(near(bounds.X, reference.X) and near(bounds.Y, reference.Y), "alignment does not change the bounds " .. tag)
     end
     reference = bounds
     if alignment == "Top" then previous = bounds.Y end
    end
   end
  end
 end
end
screen:Destroy()
return true
]==]
