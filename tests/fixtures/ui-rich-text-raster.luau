--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local font = Font.new("rbxasset://fonts/families/BuilderSans.json")
local params = Instance.new("GetTextBoundsParams")
params.Font = font
local function near(a, b) return math.abs(a - b) <= 0.001 end
local function measure(text, rich, size, width, wrapped, spacing, face)
 params.Font = face or font
 params.Text, params.RichText, params.Size = text, rich, size
 params.Width = if wrapped then width else 0
 local api = game.TextService:GetTextBoundsAsync(params)
 local label = Instance.new("TextLabel")
 label.FontFace, label.RichText = face or font, rich
 label.Text, label.TextSize = text, size
 label.TextWrapped, label.LineHeight = wrapped, spacing
 label.Size, label.Parent = UDim2.fromOffset(width, 100), screen
 task.wait(0.05)
 local bounds, fits = label.TextBounds, label.TextFits
 label:Destroy()
 return api, bounds, fits
end
local texts = {"Hi world", "<u>Hi world</u>", "<u>Save changes</u>", "<uc>Save</uc> changes", "<u>Save all of these changes now</u>"}
local unwrapped = {}
local oneLines = {}
for _, text in texts do
 for _, size in {7, 14, 18, 28} do
  for _, width in {40, 1000} do
   for _, mode in {{false, 1}, {true, 1}, {true, 1.2}} do
    local wrapped, spacing = mode[1], mode[2]
    local tag = text .. "/" .. size .. "/" .. width .. "/" .. tostring(wrapped) .. "/" .. spacing
    local api, bounds, fits = measure(text, true, size, width, wrapped, spacing)
    oneLines[size] = oneLines[size] or measure("A", true, size, 1000, false, 1)
    local oneLine = oneLines[size]
    assert(near(api.X, bounds.X), "rich service and label widths agree " .. tag)
    if spacing == 1 or api.Y <= oneLine.Y + 0.001 then
     assert(near(api.Y, bounds.Y), "rich service and label heights agree " .. tag .. ": " .. tostring(api) .. " " .. tostring(bounds))
    else
     assert(bounds.Y > api.Y and bounds.Y <= api.Y * spacing + 0.001, "line spacing only widens the gaps between lines " .. tag .. ": " .. tostring(api) .. " " .. tostring(bounds))
    end
    assert(fits == (bounds.X <= width + 0.001 and bounds.Y <= 100.001), "rich fit follows the bounds " .. tag)
    assert(bounds.Y > 0 and bounds.X > 0, "rich text has extent " .. tag)
    if wrapped and width >= 1000 then
     assert(bounds.X <= width, "rich width stays within the constraint " .. tag)
    end
    local stripped = string.gsub(text, "<[^>]*>", "")
    if string.sub(text, 1, 3) ~= "<uc" and spacing == 1 then
     local plain = measure(stripped, false, size, width, wrapped, 1)
     assert(near(plain.Y, api.Y), "rich and plain heights agree " .. tag .. ": " .. tostring(plain) .. " " .. tostring(api))
     if wrapped then
      assert(math.abs(api.X - plain.X) <= size * 0.1, "rich width differs from plain only by the trailing run " .. tag .. ": " .. tostring(plain) .. " " .. tostring(api))
     else
      assert(near(plain.X, api.X), "rich and plain widths agree " .. tag .. ": " .. tostring(plain) .. " " .. tostring(api))
     end
    end
    if not wrapped then
     unwrapped[text .. "/" .. width .. "/" .. size] = bounds
    end
   end
  end
 end
 for _, width in {40, 1000} do
  local previous = nil
  for _, size in {7, 14, 18, 28} do
   local bounds = unwrapped[text .. "/" .. width .. "/" .. size]
   if previous then
    assert(bounds.X >= previous.X - 0.001 and bounds.Y >= previous.Y - 0.001, "unwrapped bounds grow with size " .. text .. "/" .. size)
   end
   previous = bounds
  end
 end
end
local bold = Font.new(font.Family, Enum.FontWeight.Bold)
for _, text in {"<b>Lap record</b>", "<b>Lap <b>record</b></b>", "<u><b>Lap record</b></u>"} do
 for _, size in {7, 14, 18, 28} do
  for _, width in {40, 1000} do
   for _, mode in {{false, 1}, {true, 1}, {true, 1.2}} do
    local wrapped, spacing = mode[1], mode[2]
    local api, bounds, fits = measure(text, true, size, width, wrapped, spacing)
    local expected, painted, expectedFits = measure("Lap record", true, size, width, wrapped, spacing, bold)
    assert(near(api.X, expected.X) and near(api.Y, expected.Y), "bold markup uses the bold service face")
    assert(near(bounds.X, painted.X) and near(bounds.Y, painted.Y), "bold markup uses the bold label face")
    assert(fits == expectedFits, "bold markup preserves bold fit")
   end
  end
 end
end
for _, selection in {{"BuilderSans", "Bold"}, {"Fondamento", "Regular"}, {"Michroma", "Regular"}} do
 local family = "rbxasset://fonts/families/" .. selection[1] .. ".json"
 local base = Font.new(family)
 local heavy = Font.new(family, Enum.FontWeight.Heavy)
 local selected = Font.new(family, Enum.FontWeight[selection[2]])
 for _, size in {7, 14, 18, 28} do
  for _, width in {40, 1000} do
   for _, wrapped in {false, true} do
    local expected, painted, expectedFits = measure("Lap record", true, size, width, wrapped, 1, selected)
    for _, value in {{"Lap record", heavy}, {'<font weight="heavy">Lap record</font>', base}, {"<font weight='900'>Lap record</font>", base}} do
     local api, bounds, fits = measure(value[1], true, size, width, wrapped, 1, value[2])
     assert(near(api.X, expected.X) and near(api.Y, expected.Y), "Heavy uses the selected service face " .. family)
     assert(near(bounds.X, painted.X) and near(bounds.Y, painted.Y), "Heavy uses the selected label face " .. family)
     assert(fits == expectedFits, "Heavy preserves the selected fit " .. family)
    end
   end
  end
 end
end
local missingFamily = "rbxasset://fonts/families/DoesNotExist.json"
params.Font, params.Text = Font.new(missingFamily), "Unknown family text"
local measured, failure = pcall(function() return game.TextService:GetTextBoundsAsync(params) end)
assert(not measured and tostring(failure):find("Temp read failed.", 1, true), "the missing family fails in the service: " .. tostring(failure))
for _, weight in {"Regular", "Bold", "Heavy"} do
 for _, size in {7, 14, 28} do
  for _, width in {40, 1000} do
   for _, wrapped in {false, true} do
    for _, rich in {false, true} do
     local labels = {}
     for index, face in {
      Font.new(missingFamily, Enum.FontWeight[weight]),
      Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight[if weight == "Heavy" then "Bold" else weight]),
     } do
      local label = Instance.new("TextLabel")
      label.FontFace, label.TextSize, label.RichText = face, size, rich
      label.Text, label.TextWrapped = "Unknown family text", wrapped
      label.AutomaticSize, label.Size = Enum.AutomaticSize.Y, UDim2.fromOffset(width, 0)
      label.Parent = screen
      labels[index] = label
     end
     task.wait(0.05)
     assert(labels[1].TextBounds == labels[2].TextBounds, "the missing GUI family uses SourceSansPro metrics")
     assert(labels[1].AbsoluteSize == labels[2].AbsoluteSize, "the missing GUI family preserves automatic height")
     assert(labels[1].TextFits == labels[2].TextFits, "the missing GUI family preserves fit")
     assert(labels[1].FontFace.Family == missingFamily, "fallback preserves the assigned FontFace")
     for _, label in labels do label:Destroy() end
    end
   end
  end
 end
end
params:Destroy()
screen:Destroy()
return true
]==]
