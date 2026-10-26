--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local total = 0
for _, axis in {"X", "Y", "XY"} do
 for _, kind in {"None", "Horizontal", "Vertical", "WrapHorizontal", "WrapVertical"} do
  for _, floor in {"Offset", "Scale"} do
   for _, fraction in {0.25, 0.5, 1} do
    for _, padding in {0, 6} do
     for _, scale in {0.5, 1, 2} do
      local width, height = if floor == "Offset" then 200 else 400, if floor == "Offset" then 120 else 300
      local autoX, autoY = axis ~= "Y", axis ~= "X"
      local projectedX = fraction * (400 - padding * 2) - 4 + padding * 2
      local projectedY = fraction * (300 - padding * 2) - 2 + padding * 2
      if kind ~= "None" and ((autoX and projectedX > width) or (autoY and projectedY > height)) then continue end
      local outer = Instance.new("Frame")
      outer.Size, outer.Parent = UDim2.fromOffset(400, 300), screen
      local parent = Instance.new("Frame")
      parent.Size = if floor == "Offset" then UDim2.fromOffset(width, height) else UDim2.fromScale(1, 1)
      parent.AutomaticSize, parent.Parent = Enum.AutomaticSize[axis], outer
      local modifier = Instance.new("UIScale")
      modifier.Scale, modifier.Parent = scale, parent
      local inset = Instance.new("UIPadding")
      inset.PaddingLeft, inset.PaddingRight = UDim.new(0, padding), UDim.new(0, padding)
      inset.PaddingTop, inset.PaddingBottom, inset.Parent = UDim.new(0, padding), UDim.new(0, padding), parent
      local child = Instance.new("Frame")
      child.Size, child.Parent = UDim2.new(fraction, -4, fraction, -2), parent
      if kind ~= "None" then
       local list = Instance.new("UIListLayout")
       list.FillDirection = if kind == "Horizontal" or kind == "WrapHorizontal" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
       list.Wraps, list.Parent = kind:sub(1, 4) == "Wrap", parent
      end
      task.wait(0.05)
      local expectedWidth = if kind == "None" and floor == "Offset" and autoX then math.max(width, fraction * width - 4 + padding * 2) else width
      local expectedHeight = if kind == "None" and floor == "Offset" and autoY then math.max(height, fraction * height - 2 + padding * 2) else height
      local label = axis .. " " .. kind .. " " .. floor .. " " .. fraction .. " " .. padding .. " " .. scale
      assert(math.abs(parent.AbsoluteSize.X - expectedWidth * scale) < 0.01, label .. " parent width")
      assert(math.abs(parent.AbsoluteSize.Y - expectedHeight * scale) < 0.01, label .. " parent height")
      local expectedX = (fraction * (expectedWidth - padding * 2) - 4) * scale
      local expectedY = (fraction * (expectedHeight - padding * 2) - 2) * scale
      assert(math.abs(child.AbsoluteSize.X - expectedX) < 0.01, label .. " child width")
      assert(math.abs(child.AbsoluteSize.Y - expectedY) < 0.01, label .. " child height")
      assert(math.abs(child.AbsolutePosition.X - parent.AbsolutePosition.X - padding * scale) < 0.01, label .. " child x")
      assert(math.abs(child.AbsolutePosition.Y - parent.AbsolutePosition.Y - padding * scale) < 0.01, label .. " child y")
      if kind == "None" and padding == 0 then
       child.Position, child.AnchorPoint = UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
       task.wait(0.05)
       expectedWidth = if autoX then math.max(width, width * 0.5 + (fraction * width - 4) * 0.5 + padding * 2) else width
       expectedHeight = if autoY then math.max(height, height * 0.5 + (fraction * height - 2) * 0.5 + padding * 2) else height
       expectedX = (fraction * (expectedWidth - padding * 2) - 4) * scale
       expectedY = (fraction * (expectedHeight - padding * 2) - 2) * scale
       assert(math.abs(parent.AbsoluteSize.X - expectedWidth * scale) < 0.01, label .. " centered parent width")
       assert(math.abs(parent.AbsoluteSize.Y - expectedHeight * scale) < 0.01, label .. " centered parent height")
       assert(math.abs(child.AbsolutePosition.X - parent.AbsolutePosition.X - (expectedWidth * scale - expectedX) / 2) < 0.01, label .. " centered x")
       assert(math.abs(child.AbsolutePosition.Y - parent.AbsolutePosition.Y - (expectedHeight * scale - expectedY) / 2) < 0.01, label .. " centered y")
      end
      total += 1
      outer:Destroy()
     end
    end
   end
  end
 end
end
for _, axis in {"X", "Y", "XY"} do
 for _, minimum in {0, 80} do
  for _, fraction in {0.25, 0.5, 1} do
   for _, centered in {false, true} do
    local outer = Instance.new("Frame")
    outer.Size, outer.Parent = UDim2.fromOffset(400, 300), screen
    local parent = Instance.new("Frame")
    parent.Size, parent.AutomaticSize, parent.Parent = UDim2.fromOffset(minimum, minimum), Enum.AutomaticSize[axis], outer
    local content = Instance.new("Frame")
    content.Size, content.Parent = UDim2.fromOffset(50, 25), parent
    local relative = Instance.new("Frame")
    relative.Size = if centered then UDim2.fromOffset(20, 10) else UDim2.fromScale(fraction, fraction)
    if centered then relative.Position, relative.AnchorPoint = UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5) end
    relative.Parent = parent
    task.wait(0.05)
    local width = if axis ~= "Y" then math.max(minimum, 50) else minimum
    local height = if axis ~= "X" then math.max(minimum, 25) else minimum
    assert(math.abs(parent.AbsoluteSize.X - width) < 0.01, "intrinsic parent width")
    assert(math.abs(parent.AbsoluteSize.Y - height) < 0.01, "intrinsic parent height")
    assert(math.abs(relative.AbsoluteSize.X - (if centered then 20 else width * fraction)) < 0.01, "intrinsic child width")
    assert(math.abs(relative.AbsoluteSize.Y - (if centered then 10 else height * fraction)) < 0.01, "intrinsic child height")
    if centered then
     assert(math.abs(relative.AbsolutePosition.X - parent.AbsolutePosition.X - (width - 20) / 2) < 0.01, "intrinsic centered x")
     assert(math.abs(relative.AbsolutePosition.Y - parent.AbsolutePosition.Y - (height - 10) / 2) < 0.01, "intrinsic centered y")
    end
    outer:Destroy()
    total += 1
   end
  end
 end
end
local outer = Instance.new("Frame")
outer.Size, outer.Parent = UDim2.fromOffset(400, 300), screen
local parent = Instance.new("Frame")
parent.Size, parent.AutomaticSize, parent.Parent = UDim2.new(1, 0, 0, 0), Enum.AutomaticSize.XY, outer
local padding = Instance.new("UIPadding")
padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6)
padding.Parent = parent
local list = Instance.new("UIListLayout")
list.Padding, list.SortOrder, list.Parent = UDim.new(0, 5), Enum.SortOrder.LayoutOrder, parent
local a, b = Instance.new("Frame"), Instance.new("Frame")
a.Size, a.LayoutOrder, a.Parent = UDim2.new(1, 0, 0, 20), 0, parent
b.Size, b.LayoutOrder, b.Parent = UDim2.new(0.5, 0, 0, 10), 10, parent
local function verify(width, height, bWidth, bY)
 task.wait(0.05)
 assert(math.abs(parent.AbsoluteSize.X - width) < 0.01, "mutated automatic width")
 assert(math.abs(parent.AbsoluteSize.Y - height) < 0.01, "mutated automatic height")
 assert(math.abs(b.AbsoluteSize.X - bWidth) < 0.01, "mutated relative child width")
 assert(math.abs(b.AbsolutePosition.Y - parent.AbsolutePosition.Y - bY) < 0.01, "mutated child position")
end
verify(400, 47, 194, 31)
parent.Size = UDim2.new(1, 0, 0, 60)
verify(400, 60, 194, 31)
outer.Size = UDim2.fromOffset(240, 300)
verify(240, 60, 114, 31)
a.Visible = false
parent.Size = UDim2.new(1, 0, 0, 0)
verify(240, 22, 114, 6)
local c = Instance.new("Frame")
c.Size, c.LayoutOrder, c.Parent = UDim2.new(1, 0, 0, 30), 20, parent
verify(240, 57, 114, 6)
c:Destroy()
verify(240, 22, 114, 6)
padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 12)
verify(240, 34, 108, 12)
a.Visible = true
verify(240, 59, 108, 37)
outer:Destroy()
assert(total == 444)
screen:Destroy()
return true
]==]
