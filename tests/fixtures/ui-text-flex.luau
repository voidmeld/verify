--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size, params.Text = Font.new("rbxasset://fonts/families/BuilderSans.json"), 14, "A"
game.TextService:GetTextBoundsAsync(params)
params:Destroy()
local function near(a, b) return math.abs(a - b) <= 0.01 end
local heights = {}
for _, width in {100, 240, 800} do
 for _, padded in {false, true} do
  for _, scale in {0.5, 1, 2} do
   for _, limited in {false, true} do
    local tag = width .. "/" .. tostring(padded) .. "/" .. scale .. "/" .. tostring(limited)
    local frame = Instance.new("Frame")
    frame.Size, frame.Parent = UDim2.fromOffset(width, 200), screen
    local scaler = Instance.new("UIScale")
    scaler.Scale, scaler.Parent = scale, frame
    if padded then
     local padding = Instance.new("UIPadding")
     padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 6), UDim.new(0, 4)
     padding.Parent = frame
    end
    local list = Instance.new("UIListLayout")
    list.FillDirection, list.HorizontalFlex, list.SortOrder = Enum.FillDirection.Vertical, Enum.UIFlexAlignment.Fill, Enum.SortOrder.LayoutOrder
    list.Padding, list.Parent = UDim.new(0, 3), frame
    local labels = {}
    for index, text in {string.rep("Wrapped text ", 6), "Hello world"} do
     local label = Instance.new("TextLabel")
     label.Size, label.AutomaticSize = UDim2.fromOffset(0, 0), Enum.AutomaticSize.Y
     label.FontFace, label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"), 14
     label.Text, label.TextWrapped, label.LayoutOrder, label.Parent = text, true, index, frame
     local constraint = Instance.new("UISizeConstraint")
     constraint.MinSize = Vector2.new(1, 1)
     constraint.MaxSize = if limited then Vector2.new(180, 50) else Vector2.new(1000, 1000)
     constraint.Parent = label
     labels[index] = label
    end
    task.wait(0.05)
    local inset = if padded then 10 else 0
    local available = (width - inset) * scale
    local expectedWidth = if limited then math.min(available, 180 * scale) else available
    local first, second = labels[1], labels[2]
    for index, label in labels do
     assert(near(label.AbsoluteSize.X, expectedWidth), "flexed text fills the available width " .. tag .. "/" .. index .. ": " .. tostring(label.AbsoluteSize))
     assert(label.TextBounds.X <= label.AbsoluteSize.X + 0.001, "text stays inside its label " .. tag .. "/" .. index)
     assert(label.AbsoluteSize.Y <= (if limited then 50 * scale else 1000) + 0.001, "height respects the constraint " .. tag .. "/" .. index)
     if not limited then
      assert(near(label.AbsoluteSize.Y, label.TextBounds.Y), "automatic height follows the text " .. tag .. "/" .. index)
     end
     if label.AbsoluteSize.Y < 50 * scale - 0.5 then
      assert(label.TextFits, "unclamped text fits " .. tag .. "/" .. index)
     end
     local offset = label.AbsolutePosition - frame.AbsolutePosition
     assert(near(offset.X, (if padded then 6 * scale else 0)), "labels share the content edge " .. tag .. "/" .. index)
    end
    assert(second.TextFits and near(second.AbsoluteSize.Y, second.TextBounds.Y), "short text keeps its single line " .. tag)
    assert(near((second.AbsolutePosition - first.AbsolutePosition).Y, first.AbsoluteSize.Y + 3 * scale), "labels stack with the list padding " .. tag)
    assert(near(list.AbsoluteContentSize.Y, first.AbsoluteSize.Y + second.AbsoluteSize.Y + 3 * scale), "content height sums the children " .. tag .. ": " .. tostring(list.AbsoluteContentSize))
    assert(near(list.AbsoluteContentSize.X, available), "content width fills the frame " .. tag .. ": " .. tostring(list.AbsoluteContentSize))
    heights[tag] = first.TextBounds.Y
    frame:Destroy()
   end
  end
 end
end
for _, padded in {false, true} do
 for _, scale in {0.5, 1, 2} do
  for _, limited in {false, true} do
   local previous = math.huge
   for _, width in {100, 240, 800} do
    local current = heights[width .. "/" .. tostring(padded) .. "/" .. scale .. "/" .. tostring(limited)]
    assert(current <= previous + 0.001, "wrapped height never grows with width " .. tostring(padded) .. "/" .. scale .. "/" .. width)
    previous = current
   end
  end
 end
end
screen:Destroy()
return true
]==]
