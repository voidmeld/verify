--!strict

return [==[
local expected = game:GetService("HttpService"):JSONDecode([=[[{"direction":"Horizontal","corner":"TopLeft","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Horizontal","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Horizontal","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20],[62,13,50,20],[117,13,50,20]],"cellCount":[3,1],"count":3,"extent":[160,20]},{"direction":"Horizontal","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20],[62,13,50,20],[117,13,50,20],[7,43,50,20],[62,43,50,20]],"cellCount":[3,2],"count":5,"extent":[160,50]},{"direction":"Horizontal","corner":"TopRight","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Horizontal","corner":"TopRight","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Horizontal","corner":"TopRight","cellSize":[50,20],"cells":[[117,13,50,20],[62,13,50,20],[7,13,50,20]],"cellCount":[3,1],"count":3,"extent":[160,20]},{"direction":"Horizontal","corner":"TopRight","cellSize":[50,20],"cells":[[117,13,50,20],[62,13,50,20],[7,13,50,20],[117,43,50,20],[62,43,50,20]],"cellCount":[3,2],"count":5,"extent":[160,50]},{"direction":"Horizontal","corner":"BottomLeft","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Horizontal","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Horizontal","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,13,50,20],[62,13,50,20],[117,13,50,20]],"cellCount":[3,1],"count":3,"extent":[160,20]},{"direction":"Horizontal","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,43,50,20],[62,43,50,20],[117,43,50,20],[7,13,50,20],[62,13,50,20]],"cellCount":[3,2],"count":5,"extent":[160,50]},{"direction":"Horizontal","corner":"BottomRight","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Horizontal","corner":"BottomRight","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Horizontal","corner":"BottomRight","cellSize":[50,20],"cells":[[117,13,50,20],[62,13,50,20],[7,13,50,20]],"cellCount":[3,1],"count":3,"extent":[160,20]},{"direction":"Horizontal","corner":"BottomRight","cellSize":[50,20],"cells":[[117,43,50,20],[62,43,50,20],[7,43,50,20],[117,13,50,20],[62,13,50,20]],"cellCount":[3,2],"count":5,"extent":[160,50]},{"direction":"Vertical","corner":"TopLeft","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Vertical","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Vertical","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20],[7,43,50,20],[7,73,50,20]],"cellCount":[1,3],"count":3,"extent":[50,80]},{"direction":"Vertical","corner":"TopLeft","cellSize":[50,20],"cells":[[7,13,50,20],[7,43,50,20],[7,73,50,20],[62,13,50,20],[62,43,50,20]],"cellCount":[2,3],"count":5,"extent":[105,80]},{"direction":"Vertical","corner":"TopRight","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Vertical","corner":"TopRight","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Vertical","corner":"TopRight","cellSize":[50,20],"cells":[[7,13,50,20],[7,43,50,20],[7,73,50,20]],"cellCount":[1,3],"count":3,"extent":[50,80]},{"direction":"Vertical","corner":"TopRight","cellSize":[50,20],"cells":[[62,13,50,20],[62,43,50,20],[62,73,50,20],[7,13,50,20],[7,43,50,20]],"cellCount":[2,3],"count":5,"extent":[105,80]},{"direction":"Vertical","corner":"BottomLeft","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Vertical","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Vertical","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,73,50,20],[7,43,50,20],[7,13,50,20]],"cellCount":[1,3],"count":3,"extent":[50,80]},{"direction":"Vertical","corner":"BottomLeft","cellSize":[50,20],"cells":[[7,73,50,20],[7,43,50,20],[7,13,50,20],[62,73,50,20],[62,43,50,20]],"cellCount":[2,3],"count":5,"extent":[105,80]},{"direction":"Vertical","corner":"BottomRight","cellSize":[50,20],"cells":[],"cellCount":[0,0],"count":0,"extent":[0,0]},{"direction":"Vertical","corner":"BottomRight","cellSize":[50,20],"cells":[[7,13,50,20]],"cellCount":[1,1],"count":1,"extent":[50,20]},{"direction":"Vertical","corner":"BottomRight","cellSize":[50,20],"cells":[[7,73,50,20],[7,43,50,20],[7,13,50,20]],"cellCount":[1,3],"count":3,"extent":[50,80]},{"direction":"Vertical","corner":"BottomRight","cellSize":[50,20],"cells":[[62,73,50,20],[62,43,50,20],[62,13,50,20],[7,73,50,20],[7,43,50,20]],"cellCount":[2,3],"count":5,"extent":[105,80]},{"frameSize":[300,76],"cellSize":[45,30],"cellCount":[3,2],"cells":[[4,0,45,30],[57,0,45,30],[110,0,45,30],[4,46,45,30],[57,46,45,30],[110,46,45,30]],"aspectType":"FitWithinMaxSize","extent":[151,76],"axis":"Width"},{"frameSize":[300,76],"cellSize":[45,30],"cellCount":[3,2],"cells":[[4,0,45,30],[57,0,45,30],[110,0,45,30],[4,46,45,30],[57,46,45,30],[110,46,45,30]],"aspectType":"FitWithinMaxSize","extent":[151,76],"axis":"Height"},{"frameSize":[300,139.55557250976562],"cellSize":[92.66667175292969,61.77778244018555],"cellCount":[3,2],"cells":[[4,0,92.66667175292969,61.77778625488281],[104.66666412353516,0,92.66667175292969,61.77778625488281],[205.33334350585938,0,92.66667175292969,61.77778625488281],[4,77.77778625488281,92.66667175292969,61.77778625488281],[104.66666412353516,77.77778625488281,92.66667175292969,61.77778625488281],[205.33334350585938,77.77778625488281,92.66667175292969,61.77778625488281]],"aspectType":"ScaleWithParentSize","extent":[294,139.55557250976562],"axis":"Width"},{"frameSize":[300,76],"cellSize":[45,30],"cellCount":[3,2],"cells":[[4,0,45,30],[57,0,45,30],[110,0,45,30],[4,46,45,30],[57,46,45,30],[110,46,45,30]],"aspectType":"ScaleWithParentSize","extent":[151,76],"axis":"Height"}]]=])
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset = true
screen.Parent = game:GetService("Players").LocalPlayer.PlayerGui
local function near(actual, wanted, label)
    assert(math.abs(actual - wanted) < 0.001, label .. ": " .. actual .. " ~= " .. wanted)
end
local ok, failure = pcall(function()
    for _, observation in expected do
        local frame = Instance.new("Frame")
        local grid = Instance.new("UIGridLayout")
        local padding = Instance.new("UIPadding")
        frame.Parent = screen
        grid.Parent = frame
        padding.Parent = frame
        grid.SortOrder = Enum.SortOrder.LayoutOrder
        grid.FillDirectionMaxCells = 3
        if observation.aspectType then
            frame.Size = UDim2.fromOffset(300, 0)
            frame.AutomaticSize = Enum.AutomaticSize.Y
            padding.PaddingLeft = UDim.new(0, 4)
            grid.CellSize = UDim2.new(1 / 3, -6, 0, 30)
            grid.CellPadding = UDim2.fromOffset(8, 16)
            local aspect = Instance.new("UIAspectRatioConstraint")
            aspect.AspectRatio = 1.5
            aspect.AspectType = Enum.AspectType[observation.aspectType]
            aspect.DominantAxis = Enum.DominantAxis[observation.axis]
            aspect.Parent = grid
        else
            frame.Size = UDim2.fromOffset(200, 150)
            padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 7), UDim.new(0, 11)
            padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 13), UDim.new(0, 17)
            grid.CellSize = UDim2.fromOffset(50, 20)
            grid.CellPadding = UDim2.fromOffset(5, 10)
            grid.FillDirection = Enum.FillDirection[observation.direction]
            grid.StartCorner = Enum.StartCorner[observation.corner]
        end
        local cells = {}
        for index = 1, #observation.cells do
            local cell = Instance.new("Frame")
            cell.LayoutOrder, cell.Parent = index, frame
            cells[index] = cell
        end
        task.wait(0.05)
        for index, cell in cells do
            local actual = cell.AbsolutePosition - frame.AbsolutePosition
            local wanted = observation.cells[index]
            near(actual.X, wanted[1], "cell x")
            near(actual.Y, wanted[2], "cell y")
            near(cell.AbsoluteSize.X, wanted[3], "cell width")
            near(cell.AbsoluteSize.Y, wanted[4], "cell height")
        end
        near(grid.AbsoluteContentSize.X, observation.extent[1], "content width")
        near(grid.AbsoluteContentSize.Y, observation.extent[2], "content height")
        near(grid.AbsoluteCellCount.X, observation.cellCount[1], "column count")
        near(grid.AbsoluteCellCount.Y, observation.cellCount[2], "row count")
        near(grid.AbsoluteCellSize.X, observation.cellSize[1], "cell size x")
        near(grid.AbsoluteCellSize.Y, observation.cellSize[2], "cell size y")
        if observation.frameSize then
            near(frame.AbsoluteSize.X, observation.frameSize[1], "automatic width")
            near(frame.AbsoluteSize.Y, observation.frameSize[2], "automatic height")
        end
        frame:Destroy()
    end
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(210, 100)
    frame.Parent = screen
    local grid = Instance.new("UIGridLayout")
    grid.CellSize, grid.CellPadding = UDim2.new(1 / 3, -4, 0, 30), UDim2.fromOffset(6, 6)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.FillDirectionMaxCells = 3
    grid.Parent = frame
    local fourth
    for index = 1, 4 do
        local cell = Instance.new("Frame")
        cell.LayoutOrder, cell.Parent = index, frame
        fourth = cell
    end
    task.wait(0.05)
    near(grid.AbsoluteCellSize.X, 66, "scaled cell width")
    near(grid.AbsoluteCellCount.X, 3, "scaled column count")
    near(fourth.AbsolutePosition.X - frame.AbsolutePosition.X, 0, "wrapped column")
    frame:Destroy()
end)
screen:Destroy()
assert(ok, failure)
return true
]==]
