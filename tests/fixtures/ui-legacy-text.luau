--!strict

return [==[
local function near(a, b, e) return math.abs(a - b) <= (e or 0.001) end
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size = Font.new("rbxasset://fonts/families/LegacyArial.json"), 14
params.Text = "A"
game.TextService:GetTextBoundsAsync(params)
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local texts = {"", "Hello world", string.rep("Wrapped text ", 6), "Hello\nworld"}
for _, scale in {0.5, 1, 2} do
 for _, lineHeight in {1, 1.2, 2} do
  for index, text in texts do
   local tag = scale .. "/" .. lineHeight .. "/" .. index
   local frame = Instance.new("Frame")
   frame.Size, frame.Parent = UDim2.fromOffset(200, 500), screen
   local scaler = Instance.new("UIScale")
   scaler.Scale, scaler.Parent = scale, frame
   local label = Instance.new("TextLabel")
   label.FontFace, label.TextSize, label.LineHeight = params.Font, 14, lineHeight
   label.Text, label.TextWrapped = text, true
   label.Size, label.AutomaticSize = UDim2.fromOffset(100, 0), Enum.AutomaticSize.Y
   label.Parent = frame
   task.wait(0.05)
   params.Text, params.Width = text, 100
   local api = game.TextService:GetTextBoundsAsync(params)
   local bounds, size = label.TextBounds, label.AbsoluteSize
   assert(near(size.X, 100 * scale), "legacy automatic height keeps the width " .. tag)
   assert(near(size.Y, bounds.Y), "legacy automatic height follows the bounds " .. tag .. ": " .. tostring(size) .. " " .. tostring(bounds))
   assert(bounds.X <= 100 * scale + 0.001, "legacy wrapped width stays within the constraint " .. tag)
   assert((text == "") == (bounds.X == 0) and (text == "") == (api.X == 0), "only empty text has zero width " .. tag)
   if lineHeight == 1 and index <= 2 then
    assert(near(bounds.Y, api.Y * scale, math.max(1, api.Y * scale * 0.1)) and near(bounds.X, api.X * scale, math.max(2, api.X * scale * 0.1)), "legacy label bounds follow the service scaled " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(api))
   end
   if lineHeight > 1 then
    assert(bounds.Y >= api.Y * scale - 1, "line spacing never shrinks the label " .. tag)
   end
   local function legacy(height)
    return game.TextService:GetTextSize(text, 14, Enum.Font.Legacy, Vector2.new(100, height))
   end
   local full = legacy(1000000)
   assert(near(full.X, api.X) and near(full.Y, api.Y), "legacy enum agrees with the font face " .. tag .. ": " .. tostring(full) .. " " .. tostring(api))
   local line = legacy(0).Y
   local lines = math.floor(full.Y / line + 0.5)
   local previous = 0
   for _, height in {0, 20, 21, 41, 42, 50, 100, 1000} do
    local limited = legacy(height)
    local expected = math.min(lines, math.max(1, math.floor(height / line + 0.0001))) * line
    assert(near(limited.Y, expected, 0.01) and near(limited.X, full.X), "legacy enum line limit " .. tag .. "/" .. height .. ": " .. tostring(limited))
    assert(limited.Y >= previous - 0.001, "legacy line limit grows monotonically " .. tag)
    previous = limited.Y
   end
   frame:Destroy()
  end
 end
end
params:Destroy()
screen:Destroy()
return true
]==]
