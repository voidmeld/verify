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
return true
]]
