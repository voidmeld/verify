--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local font = Font.new("rbxasset://fonts/families/BuilderSans.json")
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size, params.Width = font, 14, 0
local texts = {"Hi world", "A V", "T o", "A  B  C", "Hi world ", " Hi world", "one two three", "AB"}
local function near(a, b) return math.abs(a - b) <= 0.001 end
for _, rich in {false, true} do
 for _, text in texts do
  params.Text = text
  local service = game.TextService:GetTextBoundsAsync(params)
  for _, offset in {-6, -1, 0, 1, 6} do
   for _, height in {0, 7, 100} do
    local width = math.max(1, math.floor(service.X) + offset)
    local label = Instance.new("TextLabel")
    label.FontFace, label.TextSize = font, 14
    label.RichText = rich
    label.Text = if rich then "<u>" .. text .. "</u>" else text
    label.Size, label.Parent = UDim2.fromOffset(width, height), screen
    task.wait(0.05)
    local bounds, fits = label.TextBounds, label.TextFits
    local tag = tostring(rich) .. "/" .. text .. "/" .. width .. "/" .. height
    assert(near(bounds.Y, service.Y), "single line height " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(service))
    if rich then
     assert(near(bounds.X, service.X), "rich bounds keep the full advance " .. tag .. ": " .. tostring(bounds) .. " " .. tostring(service))
     assert(fits == (bounds.X <= width + 0.001 and height >= bounds.Y - 0.001), "rich fit follows the bounds " .. tag)
    else
     assert(bounds.X <= service.X + 0.001, "plain bounds never exceed the full advance " .. tag)
     if fits then
      assert(bounds.X <= width + 0.001, "a fitting label stays inside its width " .. tag)
     end
     if width >= service.X and height >= bounds.Y then
      assert(fits and near(bounds.X, service.X), "a roomy label fits at the full advance " .. tag)
     end
     if bounds.X > width + 0.001 then
      assert(not fits, "an overflowing label does not fit " .. tag)
     end
    end
    label:Destroy()
   end
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
assert(near(automatic.AbsoluteSize.X, automatic.TextBounds.X), "automatic width follows the text")
automatic:Destroy()
params:Destroy()
screen:Destroy()
return true
]==]
