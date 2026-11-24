--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local function near(a, b) return math.abs(a - b) <= 0.01 end
local function clamp(value, low, high) return math.min(math.max(value, low), high) end
local function observe(class, axis, limits, wrapped)
 local object = Instance.new(class)
 object.Size, object.AutomaticSize = UDim2.fromOffset(100, 0), Enum.AutomaticSize[axis]
 object.Parent = screen
 if class == "Frame" then
  local child = Instance.new("Frame")
  child.Size, child.Parent = UDim2.fromOffset(120, 80), object
 else
  object.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
  object.TextSize, object.TextWrapped = 14, wrapped
  object.Text = string.rep("Wrapped text ", 6)
 end
 local constraint = Instance.new("UISizeConstraint")
 constraint.MinSize, constraint.MaxSize = Vector2.new(limits[1][1], limits[1][2]), Vector2.new(limits[2][1], limits[2][2])
 constraint.Parent = object
 task.wait(0.05)
 local size, bounds, fits = object.AbsoluteSize, nil, nil
 if class == "TextLabel" then
  bounds, fits = object.TextBounds, object.TextFits
 end
 object:Destroy()
 return size, bounds, fits
end
local free = {{0, 0}, {1000, 1000}}
local cases = {free, {{80, 40}, {1000, 1000}}, {{0, 0}, {50, 40}}, {{80, 40}, {100, 60}}}
local line = observe("TextLabel", "XY", free, false).Y
local clamped = 0
for _, class in {"Frame", "TextLabel"} do
 for _, axis in {"X", "Y", "XY"} do
  for _, wrapped in {false, true} do
   if class == "Frame" and wrapped then continue end
   local reference = observe(class, axis, free, wrapped)
   for index, limits in cases do
    local tag = class .. "/" .. axis .. "/" .. tostring(wrapped) .. "/" .. index
    local size, bounds, fits = observe(class, axis, limits, wrapped)
    local base = {100, 0}
    local content = {reference.X, reference.Y}
    local final = {size.X, size.Y}
    for slot, name in {"X", "Y"} do
     local automatic = string.find(axis, name, 1, true) ~= nil
     local wanted = clamp(if automatic then content[slot] else base[slot], limits[1][slot], limits[2][slot])
     if class == "Frame" and automatic then
      wanted = math.max(content[slot], limits[1][slot])
     elseif class == "TextLabel" and automatic and slot == 2 then
      wanted = math.max(limits[1][2], math.min(content[2], math.max(math.floor(limits[2][2] / line + 0.0001), 1) * line))
     end
     if class == "TextLabel" and slot == 2 and wrapped and not near(final[1], content[1]) and automatic then
      local lines = math.floor(final[2] / line + 0.0001)
      assert(final[2] >= wanted - 0.01 and final[2] <= math.max(limits[2][2], limits[1][2], line) + 0.01, "narrowed wrapped text grows taller within the limits " .. tag .. ": " .. tostring(size))
      assert(near(final[2], lines * line) or near(final[2], limits[1][2]), "narrowed wrapped height is whole lines " .. tag)
     else
      assert(near(final[slot], wanted), "automatic size follows its constraint " .. tag .. "/" .. name .. ": " .. tostring(size) .. " wanted " .. wanted)
     end
     if not near(final[slot], content[slot]) and automatic then
      clamped += 1
     end
    end
    if class == "TextLabel" then
     if fits then
      assert(bounds.X <= size.X + 0.01 and bounds.Y <= size.Y + 0.01, "fitting text lies inside the label " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(size))
     end
     assert(bounds.X <= size.X + 0.01 or not wrapped, "wrapped text stays inside the width " .. tag)
     if index == 1 and axis == "XY" then
      assert(fits, "unconstrained automatic text fits " .. tag)
      assert(near(bounds.X, size.X) and near(bounds.Y, size.Y), "unconstrained automatic size is the text bounds " .. tag)
     end
    end
   end
  end
 end
end
assert(clamped > 0, "constraints clamp some automatic axes")
screen:Destroy()
return true
]==]
