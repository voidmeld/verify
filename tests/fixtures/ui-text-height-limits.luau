--!strict

return [==[
local text = string.rep("Wrapped text ", 6)
local heights = {0, 20, 40, 61, 62, 63, 82, 83, 103, 104, 124, 125, 200, 248, 249}
for _, font in {"Legacy", "BuilderSans"} do
 for _, size in {7, 14, 15, 19} do
  local function measure(height)
   return game.TextService:GetTextSize(text, size, Enum.Font[font], Vector2.new(100, height))
  end
  local full = measure(1000000)
  local line = measure(0).Y
  local lines = math.floor(full.Y / line + 0.5)
  local label = font .. "/" .. size
  assert(line > 0 and lines >= 2, "wrapped text spans several lines " .. label)
  assert(math.abs(full.Y - lines * line) < 0.01, "full height is whole lines " .. label)
  assert(full.X <= 100, "width stays within the constraint " .. label)
  local sample = table.clone(heights)
  for step = 0, lines + 1 do
   table.insert(sample, step * line)
   table.insert(sample, step * line + line * 0.5)
   table.insert(sample, step * line - 0.5)
  end
  table.sort(sample)
  local previous = 0
  for _, height in sample do
   local bounds = measure(math.max(height, 0))
   local expected = math.min(lines, math.max(1, math.floor(height / line + 0.0001))) * line
   assert(math.abs(bounds.Y - expected) < 0.01, "height " .. height .. " clamps to whole lines " .. label .. ": " .. tostring(bounds))
   assert(bounds.X == full.X, "width ignores the height limit " .. label)
   assert(bounds.Y >= previous, "height grows monotonically " .. label)
   previous = bounds.Y
  end
 end
end
return true
]==]
