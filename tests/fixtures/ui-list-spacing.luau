--!strict

return [[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset = true
screen.Parent = game:GetService("Players").LocalPlayer.PlayerGui
local expected = {
    SpaceBetween = { {}, { 0 }, { 0, 180 }, { 0, 90, 180 } },
    SpaceAround = { {}, { 90 }, { 40, 140 }, { 70 / 3, 90, 470 / 3 } },
    SpaceEvenly = { {}, { 90 }, { 160 / 3, 380 / 3 }, { 35, 90, 145 } },
}
local ok, failure = pcall(function()
    for _, direction in { Enum.FillDirection.Horizontal, Enum.FillDirection.Vertical } do
        local horizontal = direction == Enum.FillDirection.Horizontal
        for _, flex in { Enum.UIFlexAlignment.SpaceBetween, Enum.UIFlexAlignment.SpaceAround, Enum.UIFlexAlignment.SpaceEvenly } do
            for count = 0, 3 do
                local row = Instance.new("Frame")
                row.Size = UDim2.fromOffset(200, 200)
                row.Parent = screen
                local list = Instance.new("UIListLayout")
                list.FillDirection = direction
                list.Padding = UDim.new(0, 8)
                list.SortOrder = Enum.SortOrder.LayoutOrder
                list[if horizontal then "HorizontalFlex" else "VerticalFlex"] = flex
                list.Parent = row
                local children = {}
                for index = 1, count do
                    local child = Instance.new("Frame")
                    child.Size = UDim2.fromOffset(20, 20)
                    child.LayoutOrder = index
                    child.Parent = row
                    table.insert(children, child)
                end
                task.wait(0.05)
                for index, child in children do
                    local position = child.AbsolutePosition - row.AbsolutePosition
                    local actual = if horizontal then position.X else position.Y
                    assert(math.abs(actual - expected[flex.Name][count + 1][index]) < 0.001, flex.Name .. " position")
                end
                local extent = list.AbsoluteContentSize
                local main = count * 20 + math.max(0, count - 1) * 8
                assert((if horizontal then extent.X else extent.Y) == main, flex.Name .. " content extent")
                assert((if horizontal then extent.Y else extent.X) == (if count == 0 then 0 else 20), flex.Name .. " cross extent")
                row:Destroy()
            end
        end
    end
end)
screen:Destroy()
assert(ok, failure)
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,horizontal in {true,false} do
 for _,alignment in {"Leading","Center","Trailing"} do
  for _,flex in {Enum.UIFlexAlignment.SpaceBetween,Enum.UIFlexAlignment.SpaceAround,Enum.UIFlexAlignment.SpaceEvenly} do
   for count=1,3 do
    for _,gap in {0,8} do
     local frame=Instance.new("Frame")
     frame.Size,frame.Parent=UDim2.fromOffset(100,100),screen
     local padding=Instance.new("UIPadding")
     padding.PaddingLeft,padding.PaddingRight,padding.PaddingTop,padding.PaddingBottom,padding.Parent=UDim.new(0,3),UDim.new(0,7),UDim.new(0,3),UDim.new(0,7),frame
     local list=Instance.new("UIListLayout")
     list.FillDirection=if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
     list.Padding,list[if horizontal then "HorizontalFlex" else "VerticalFlex"],list.Parent=UDim.new(0,gap),flex,frame
     list[if horizontal then "HorizontalAlignment" else "VerticalAlignment"]=if horizontal then Enum.HorizontalAlignment[if alignment=="Leading" then "Left" elseif alignment=="Trailing" then "Right" else alignment] else Enum.VerticalAlignment[if alignment=="Leading" then "Top" elseif alignment=="Trailing" then "Bottom" else alignment]
     local children={}
     for index=1,count do
      local child=Instance.new("Frame")
      child.Size,child.LayoutOrder,child.Parent=if horizontal then UDim2.fromOffset(100,20) else UDim2.fromOffset(20,100),index,frame
      table.insert(children,child)
     end
     task.wait(.05)
     local extent=count*100+(count-1)*gap
     local first=3+(if flex==Enum.UIFlexAlignment.SpaceBetween then 0 else (90-extent)/2)
     for index,child in children do
      local position=child.AbsolutePosition-frame.AbsolutePosition
      assert(math.abs((if horizontal then position.X else position.Y)-(first+(index-1)*(100+gap)))<.001,"overflowing spacing keeps its authored gap")
     end
     assert((if horizontal then list.AbsoluteContentSize.X else list.AbsoluteContentSize.Y)==extent,"overflowing content includes padding")
     frame:Destroy()
    end
   end
  end
 end
end
screen:Destroy()
return true
]]
