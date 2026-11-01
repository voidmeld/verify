--!strict

return [==[
local function near(a, b, e) return math.abs(a - b) <= (e or 0.001) end
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size = Font.new("rbxasset://fonts/families/BuilderSans.json"), 14
params.Text = "A"
game.TextService:GetTextBoundsAsync(params)
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local texts = {"", "Hello world", string.rep("Wrapped text ", 6), "Hello\nworld"}
for _, scale in {0.5, 1, 2} do
 local seen = {}
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
   local legacy = game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, 0))
   local bounds, size = label.TextBounds, label.AbsoluteSize
   local line = game.TextService:GetTextSize("A", 14, Enum.Font.BuilderSans, Vector2.new(100, 0)).Y
   assert(near(legacy.X, api.X) and near(legacy.Y, line), "legacy text API limits the height to one line " .. tag .. ": " .. tostring(legacy))
   local lines = math.floor(api.Y / line + 0.5)
   for _, height in {13, 14, 20, 28, 100} do
    local limited = game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, height))
    local expected = math.min(lines, math.max(1, math.floor(height / line))) * line
    assert(near(limited.X, api.X) and near(limited.Y, expected, 0.01), "legacy text API limits the height to whole lines " .. tag .. "/" .. height .. ": " .. tostring(limited))
   end
   local full = game.TextService:GetTextSize(text, 14, Enum.Font.BuilderSans, Vector2.new(100, 1000000))
   assert(near(full.X, api.X) and near(full.Y, api.Y), "legacy text API with room agrees with the service " .. tag)
   assert(near(size.X, 100 * scale), "automatic height keeps the width " .. tag)
   assert(near(size.Y, bounds.Y), "automatic height follows the text bounds " .. tag .. ": " .. tostring(size) .. " " .. tostring(bounds))
   assert(bounds.X <= 100 * scale + 0.001, "wrapped width stays within the constraint " .. tag)
   assert((text == "") == (bounds.X == 0) and (text == "") == (api.X == 0), "only empty text has zero width " .. tag)
   if lineHeight == 1 and index ~= 3 then
    assert(near(bounds.Y, api.Y * scale, math.max(1, api.Y * scale * 0.1)), "label height follows the service scaled " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(api))
   elseif lineHeight > 1 then
    assert(bounds.Y >= seen[scale .. "/1/" .. index].Y - 0.001, "line spacing never shrinks the label " .. tag)
   end
   seen[scale .. "/" .. lineHeight .. "/" .. index] = bounds
   frame:Destroy()
  end
 end
end
for _, automatic in {"None", "X", "Y", "XY"} do
 for _, extent in {{0, 0}, {10, 8}, {100, 100}} do
  for _, padded in {false, true} do
   local tag = automatic .. "/" .. extent[1] .. "/" .. tostring(padded)
   local label = Instance.new("TextLabel")
   label.FontFace, label.TextSize = params.Font, 14
   label.Text, label.TextWrapped = "Hello", false
   label.Size, label.AutomaticSize = UDim2.fromOffset(extent[1], extent[2]), Enum.AutomaticSize[automatic]
   label.Parent = screen
   if padded then
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 2), UDim.new(0, 4)
    padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 3), UDim.new(0, 5)
    padding.Parent = label
   end
   task.wait(0.05)
   params.Text, params.Width = "Hello", 0
   local natural = game.TextService:GetTextBoundsAsync(params)
   local bounds, size = label.TextBounds, label.AbsoluteSize
   local padX, padY = if padded then 6 else 0, if padded then 8 else 0
   assert(near(bounds.X, natural.X) and near(bounds.Y, natural.Y), "unwrapped bounds are the natural text size " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(natural))
   local wantX = if automatic == "X" or automatic == "XY" then math.max(extent[1], natural.X + padX) else extent[1]
   local wantY = if automatic == "Y" or automatic == "XY" then math.max(extent[2], natural.Y + padY) else extent[2]
   assert(near(size.X, wantX) and near(size.Y, wantY), "automatic axes grow to the padded text " .. tag .. ": " .. tostring(size))
   assert(label.TextFits == (natural.X + padX <= size.X + 0.001 and natural.Y + padY <= size.Y + 0.001), "fit compares the text with the padded area " .. tag)
   label:Destroy()
  end
 end
end
params.Size, params.Text, params.Width = 16, "The quick brown fox jumps over the lazy dog", 0
local natural = game.TextService:GetTextBoundsAsync(params)
for index, mode in { "AtEnd", "SplitWord" } do
 local label = Instance.new("TextLabel")
 label.FontFace, label.TextSize = params.Font, 16
 label.Text = params.Text
 label.Size, label.TextTruncate = UDim2.fromOffset(600, 20), Enum.TextTruncate[mode]
 label.Parent = screen
 task.wait(0.05)
 assert(near(label.AbsoluteSize.X, 600) and near(label.AbsoluteSize.Y, 20), "fitting truncated size " .. index)
 assert(near(label.TextBounds.X, natural.X) and near(label.TextBounds.Y, natural.Y), "fitting truncation leaves the bounds " .. index .. ": " .. tostring(label.TextBounds))
 assert(label.TextFits == true, "fitting truncated text fits " .. index)
 label:Destroy()
end
local automaticTruncated = Instance.new("TextLabel")
automaticTruncated.FontFace, automaticTruncated.TextSize = params.Font, 16
automaticTruncated.Text = params.Text
automaticTruncated.Size, automaticTruncated.AutomaticSize = UDim2.fromOffset(0, 20), Enum.AutomaticSize.X
automaticTruncated.TextTruncate, automaticTruncated.Parent = Enum.TextTruncate.AtEnd, screen
task.wait(0.05)
assert(near(automaticTruncated.AbsoluteSize.X, natural.X) and near(automaticTruncated.AbsoluteSize.Y, 20), "automatic size ignores truncation")
assert(near(automaticTruncated.TextBounds.X, natural.X) and near(automaticTruncated.TextBounds.Y, natural.Y), "automatic truncated text bounds")
automaticTruncated:Destroy()
params:Destroy()
screen:Destroy()
return true
]==]
