--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local font = Font.new("rbxasset://fonts/families/BuilderSans.json")
local function observe(text, mode, width, height, wrapped)
 local label = Instance.new("TextLabel")
 label.FontFace = font
 label.TextSize, label.Text = 16, text
 label.TextWrapped, label.TextTruncate = wrapped, Enum.TextTruncate[mode]
 label.Size, label.Parent = UDim2.fromOffset(width, height), screen
 task.wait(0.05)
 local bounds, fits = label.TextBounds, label.TextFits
 label:Destroy()
 return bounds, fits
end
local line = observe("A", "None", 1000, 1000, false).Y
local texts = {"Confirm the selected driver and race details before continuing.", "selected driver and race details before continuing.", "Confirm the selected driver "}
for count = 1, 12, 4 do
 table.insert(texts, string.rep("A", count) .. " " .. string.rep("B", 16) .. " " .. string.rep("C", 16))
end
local rows = {{60, 16, false}, {100, 16, false}, {140, 16, false}}
for _, width in {100, 120} do
 for _, height in {16, 32, 48} do
  for _, wrapped in {false, true} do
   table.insert(rows, {width, height, wrapped})
  end
 end
end
local reduced = 0
for textIndex, text in texts do
 for _, row in rows do
  local width, height, wrapped = row[1], row[2], row[3]
  if wrapped and textIndex > 3 then continue end
  local full = observe(text, "None", width, 1000, wrapped)
  local plain, plainFits = observe(text, "None", width, height, wrapped)
  assert(plain.Y <= math.max(height, line) + 0.001, "untruncated height stays within the limit")
  assert(math.abs(plain.Y / line - math.floor(plain.Y / line + 0.5)) < 0.01, "untruncated height is whole lines")
  local fitsAll = full.X <= width + 0.001 and full.Y <= height + 0.001
  for _, mode in {"AtEnd", "SplitWord"} do
   local tag = mode .. "/" .. width .. "/" .. height .. "/" .. tostring(wrapped) .. "/" .. #text
   local bounds, fits = observe(text, mode, width, height, wrapped)
   assert(bounds.X <= width + math.max(1.01, width * 0.05), "truncated width stays within the bounds " .. tag .. ": " .. tostring(bounds))
   assert(bounds.Y <= math.max(height, line) + 0.001 and bounds.Y <= plain.Y + 0.001, "truncated height stays within the bounds " .. tag .. ": " .. tostring(bounds))
   assert(math.abs(bounds.Y / line - math.floor(bounds.Y / line + 0.5)) < 0.01, "truncated height is whole lines " .. tag)
   if fitsAll then
    assert(fits and plainFits, "fitting text is untouched " .. tag)
    assert(math.abs(bounds.X - plain.X) < 0.001 and math.abs(bounds.Y - plain.Y) < 0.001, "fitting text keeps its bounds " .. tag)
   elseif not wrapped then
    assert(not fits, "overflowing text does not fit " .. tag)
    assert(bounds.X < full.X, "truncation removes content " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(full))
    reduced += 1
   end
  end
 end
end
assert(reduced > 0, "some rows truncate")
screen:Destroy()
return true
]==]
