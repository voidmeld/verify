--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local texts = {"", "Hello world", "Hello\nworld", string.rep("Wrapped text ", 6)}
local function observe(family, scale, spacing, text)
 local frame = Instance.new("Frame")
 frame.Size, frame.Parent = UDim2.fromOffset(200, 500), screen
 local scaler = Instance.new("UIScale")
 scaler.Scale, scaler.Parent = scale, frame
 local label = Instance.new("TextLabel")
 label.FontFace = Font.new("rbxasset://fonts/families/" .. family .. ".json")
 label.TextSize, label.Text, label.LineHeight = 14, text, spacing
 label.TextWrapped, label.AutomaticSize = true, Enum.AutomaticSize.Y
 label.Size, label.Parent = UDim2.fromOffset(100, 0), frame
 task.wait(0.05)
 local bounds, size = label.TextBounds, label.AbsoluteSize
 frame:Destroy()
 return bounds, size
end
for _, family in {"BuilderSans", "LegacyArial"} do
 local seen = {}
 for _, scale in {0.5, 1, 2} do
  for _, spacing in {1, 1.2, 2} do
   for index, text in texts do
    local bounds, size = observe(family, scale, spacing, text)
    local tag = family .. "/" .. scale .. "/" .. spacing .. "/" .. index
    assert(math.abs(size.X - 100 * scale) < 0.001, "automatic height keeps the width " .. tag .. ": " .. tostring(size))
    assert(math.abs(size.Y - bounds.Y) < 0.001, "automatic height follows the text bounds " .. tag .. ": " .. tostring(size) .. " " .. tostring(bounds))
    assert(bounds.X <= 100 * scale + 0.001, "wrapped width stays within the constraint " .. tag)
    assert(bounds.Y > 0, "every text keeps a line " .. tag)
    seen[tag] = bounds
   end
  end
 end
 for _, scale in {0.5, 1, 2} do
  for _, spacing in {1, 1.2, 2} do
   local function at(index) return seen[family .. "/" .. scale .. "/" .. spacing .. "/" .. index] end
   local tag = family .. "/" .. scale .. "/" .. spacing
   assert(at(1).X == 0, "empty text has zero width " .. tag)
   assert(at(2).X > 0 and at(4).X > 0, "non-empty text has width " .. tag)
   assert(at(4).Y >= at(2).Y - 0.001, "wrapped text is at least one line " .. tag)
   assert(at(3).Y >= 2 * at(2).Y - 2 * scale, "a line break adds a line " .. tag)
   assert(at(1).Y <= at(2).Y + 0.001, "empty text keeps a single line height " .. tag)
  end
 end
 for _, scale in {0.5, 1, 2} do
  for index = 1, #texts do
   local previous = nil
   for _, spacing in {1, 1.2, 2} do
    local bounds = seen[family .. "/" .. scale .. "/" .. spacing .. "/" .. index]
    if previous then
     assert(bounds.Y >= previous.Y - 0.001, "line spacing never shrinks the text " .. family .. "/" .. scale .. "/" .. index)
     assert(math.abs(bounds.X - previous.X) < 0.001, "line spacing keeps the width " .. family .. "/" .. scale .. "/" .. index)
    end
    previous = bounds
   end
   local base = seen[family .. "/" .. scale .. "/1/" .. index]
   local double = seen[family .. "/" .. scale .. "/2/" .. index]
   assert(double.Y <= base.Y * 2 + 0.001, "line spacing at most scales the height " .. family .. "/" .. scale .. "/" .. index)
  end
 end
 for _, spacing in {1, 1.2, 2} do
  for index = 1, 3 do
   local half = seen[family .. "/0.5/" .. spacing .. "/" .. index]
   local full = seen[family .. "/1/" .. spacing .. "/" .. index]
   local twice = seen[family .. "/2/" .. spacing .. "/" .. index]
   assert(math.abs(half.Y * 2 - full.Y) <= math.max(2, full.Y * 0.1) and math.abs(full.Y * 2 - twice.Y) <= math.max(2, twice.Y * 0.1), "UI scale scales the height " .. family .. "/" .. spacing .. "/" .. index)
  end
 end
end
screen:Destroy()
return true
]==]
