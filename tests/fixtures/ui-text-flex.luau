--!strict

return [==[
 local screen = Instance.new("ScreenGui")
 screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
 local expected = game.HttpService:JSONDecode([=[[{"padded":false,"content":[50,50.5],"scale":0.5,"children":[{"fits":true,"bounds":[41,42],"position":[0,0],"size":[50,42]},{"fits":true,"bounds":[32,7],"position":[0,43.5],"size":[50,7]}],"limited":false,"width":100},{"padded":false,"content":[50,33.5],"scale":0.5,"children":[{"fits":false,"bounds":[41,21],"position":[0,0],"size":[50,25]},{"fits":true,"bounds":[32,7],"position":[0,26.5],"size":[50,7]}],"limited":true,"width":100},{"padded":false,"content":[100,101],"scale":1,"children":[{"fits":true,"bounds":[75,84],"position":[0,0],"size":[100,84]},{"fits":true,"bounds":[61,14],"position":[0,87],"size":[100,14]}],"limited":false,"width":100},{"padded":false,"content":[100,67],"scale":1,"children":[{"fits":false,"bounds":[75,42],"position":[0,0],"size":[100,50]},{"fits":true,"bounds":[61,14],"position":[0,53],"size":[100,14]}],"limited":true,"width":100},{"padded":false,"content":[200,202],"scale":2,"children":[{"fits":true,"bounds":[144,168],"position":[0,0],"size":[200,168]},{"fits":true,"bounds":[115,28],"position":[0,174],"size":[200,28]}],"limited":false,"width":100},{"padded":false,"content":[200,134],"scale":2,"children":[{"fits":false,"bounds":[144,84],"position":[0,0],"size":[200,100]},{"fits":true,"bounds":[115,28],"position":[0,106],"size":[200,28]}],"limited":true,"width":100},{"padded":true,"content":[45,50.5],"scale":0.5,"children":[{"fits":true,"bounds":[41,42],"position":[3,0],"size":[45,42]},{"fits":true,"bounds":[32,7],"position":[3,43.5],"size":[45,7]}],"limited":false,"width":100},{"padded":true,"content":[45,33.5],"scale":0.5,"children":[{"fits":false,"bounds":[41,21],"position":[3,0],"size":[45,25]},{"fits":true,"bounds":[32,7],"position":[3,26.5],"size":[45,7]}],"limited":true,"width":100},{"padded":true,"content":[90,101],"scale":1,"children":[{"fits":true,"bounds":[75,84],"position":[6,0],"size":[90,84]},{"fits":true,"bounds":[61,14],"position":[6,87],"size":[90,14]}],"limited":false,"width":100},{"padded":true,"content":[90,67],"scale":1,"children":[{"fits":false,"bounds":[75,42],"position":[6,0],"size":[90,50]},{"fits":true,"bounds":[61,14],"position":[6,53],"size":[90,14]}],"limited":true,"width":100},{"padded":true,"content":[180,202],"scale":2,"children":[{"fits":true,"bounds":[144,168],"position":[12,0],"size":[180,168]},{"fits":true,"bounds":[115,28],"position":[12,174],"size":[180,28]}],"limited":false,"width":100},{"padded":true,"content":[180,134],"scale":2,"children":[{"fits":false,"bounds":[144,84],"position":[12,0],"size":[180,100]},{"fits":true,"bounds":[115,28],"position":[12,106],"size":[180,28]}],"limited":true,"width":100},{"padded":false,"content":[120,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[108,21],"position":[0,0],"size":[120,21]},{"fits":true,"bounds":[32,7],"position":[0,22.5],"size":[120,7]}],"limited":false,"width":240},{"padded":false,"content":[120,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[82,21],"position":[0,0],"size":[90,21]},{"fits":true,"bounds":[32,7],"position":[0,22.5],"size":[90,7]}],"limited":true,"width":240},{"padded":false,"content":[240,45],"scale":1,"children":[{"fits":true,"bounds":[225,28],"position":[0,0],"size":[240,28]},{"fits":true,"bounds":[61,14],"position":[0,31],"size":[240,14]}],"limited":false,"width":240},{"padded":false,"content":[240,59],"scale":1,"children":[{"fits":true,"bounds":[150,42],"position":[0,0],"size":[180,42]},{"fits":true,"bounds":[61,14],"position":[0,45],"size":[180,14]}],"limited":true,"width":240},{"padded":false,"content":[480,90],"scale":2,"children":[{"fits":true,"bounds":[432,56],"position":[0,0],"size":[480,56]},{"fits":true,"bounds":[115,28],"position":[0,62],"size":[480,28]}],"limited":false,"width":240},{"padded":false,"content":[480,118],"scale":2,"children":[{"fits":true,"bounds":[288,84],"position":[0,0],"size":[360,84]},{"fits":true,"bounds":[115,28],"position":[0,90],"size":[360,28]}],"limited":true,"width":240},{"padded":true,"content":[115,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[108,21],"position":[3,0],"size":[115,21]},{"fits":true,"bounds":[32,7],"position":[3,22.5],"size":[115,7]}],"limited":false,"width":240},{"padded":true,"content":[115,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[82,21],"position":[3,0],"size":[90,21]},{"fits":true,"bounds":[32,7],"position":[3,22.5],"size":[90,7]}],"limited":true,"width":240},{"padded":true,"content":[230,45],"scale":1,"children":[{"fits":true,"bounds":[225,28],"position":[6,0],"size":[230,28]},{"fits":true,"bounds":[61,14],"position":[6,31],"size":[230,14]}],"limited":false,"width":240},{"padded":true,"content":[230,59],"scale":1,"children":[{"fits":true,"bounds":[150,42],"position":[6,0],"size":[180,42]},{"fits":true,"bounds":[61,14],"position":[6,45],"size":[180,14]}],"limited":true,"width":240},{"padded":true,"content":[460,90],"scale":2,"children":[{"fits":true,"bounds":[432,56],"position":[12,0],"size":[460,56]},{"fits":true,"bounds":[115,28],"position":[12,62],"size":[460,28]}],"limited":false,"width":240},{"padded":true,"content":[460,118],"scale":2,"children":[{"fits":true,"bounds":[288,84],"position":[12,0],"size":[360,84]},{"fits":true,"bounds":[115,28],"position":[12,90],"size":[360,28]}],"limited":true,"width":240},{"padded":false,"content":[400,15.5],"scale":0.5,"children":[{"fits":true,"bounds":[246,7],"position":[0,0],"size":[400,7]},{"fits":true,"bounds":[32,7],"position":[0,8.5],"size":[400,7]}],"limited":false,"width":800},{"padded":false,"content":[400,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[82,21],"position":[0,0],"size":[90,21]},{"fits":true,"bounds":[32,7],"position":[0,22.5],"size":[90,7]}],"limited":true,"width":800},{"padded":false,"content":[800,31],"scale":1,"children":[{"fits":true,"bounds":[450,14],"position":[0,0],"size":[800,14]},{"fits":true,"bounds":[61,14],"position":[0,17],"size":[800,14]}],"limited":false,"width":800},{"padded":false,"content":[800,59],"scale":1,"children":[{"fits":true,"bounds":[150,42],"position":[0,0],"size":[180,42]},{"fits":true,"bounds":[61,14],"position":[0,45],"size":[180,14]}],"limited":true,"width":800},{"padded":false,"content":[1600,62],"scale":2,"children":[{"fits":true,"bounds":[864,28],"position":[0,0],"size":[1600,28]},{"fits":true,"bounds":[115,28],"position":[0,34],"size":[1600,28]}],"limited":false,"width":800},{"padded":false,"content":[1600,118],"scale":2,"children":[{"fits":true,"bounds":[288,84],"position":[0,0],"size":[360,84]},{"fits":true,"bounds":[115,28],"position":[0,90],"size":[360,28]}],"limited":true,"width":800},{"padded":true,"content":[395,15.5],"scale":0.5,"children":[{"fits":true,"bounds":[246,7],"position":[3,0],"size":[395,7]},{"fits":true,"bounds":[32,7],"position":[3,8.5],"size":[395,7]}],"limited":false,"width":800},{"padded":true,"content":[395,29.5],"scale":0.5,"children":[{"fits":true,"bounds":[82,21],"position":[3,0],"size":[90,21]},{"fits":true,"bounds":[32,7],"position":[3,22.5],"size":[90,7]}],"limited":true,"width":800},{"padded":true,"content":[790,31],"scale":1,"children":[{"fits":true,"bounds":[450,14],"position":[6,0],"size":[790,14]},{"fits":true,"bounds":[61,14],"position":[6,17],"size":[790,14]}],"limited":false,"width":800},{"padded":true,"content":[790,59],"scale":1,"children":[{"fits":true,"bounds":[150,42],"position":[6,0],"size":[180,42]},{"fits":true,"bounds":[61,14],"position":[6,45],"size":[180,14]}],"limited":true,"width":800},{"padded":true,"content":[1580,62],"scale":2,"children":[{"fits":true,"bounds":[864,28],"position":[12,0],"size":[1580,28]},{"fits":true,"bounds":[115,28],"position":[12,34],"size":[1580,28]}],"limited":false,"width":800},{"padded":true,"content":[1580,118],"scale":2,"children":[{"fits":true,"bounds":[288,84],"position":[12,0],"size":[360,84]},{"fits":true,"bounds":[115,28],"position":[12,90],"size":[360,28]}],"limited":true,"width":800}]]=])
 local observationIndex = 0
 local params = Instance.new("GetTextBoundsParams")
 params.Font, params.Size, params.Text = Font.new("rbxasset://fonts/families/BuilderSans.json"),14,"A"
 game.TextService:GetTextBoundsAsync(params)
 params:Destroy()
 for _, width in {100,240,800} do
  for _, padded in {false,true} do
   for _, scale in {0.5,1,2} do
    for _, limited in {false,true} do
     local frame = Instance.new("Frame")
     frame.Size, frame.Parent = UDim2.fromOffset(width,200), screen
     local scaler = Instance.new("UIScale")
     scaler.Scale, scaler.Parent = scale,frame
     if padded then
      local padding = Instance.new("UIPadding")
      padding.PaddingLeft, padding.PaddingRight = UDim.new(0,6),UDim.new(0,4)
      padding.Parent = frame
     end
     local list = Instance.new("UIListLayout")
     list.FillDirection, list.HorizontalFlex, list.SortOrder = Enum.FillDirection.Vertical,Enum.UIFlexAlignment.Fill,Enum.SortOrder.LayoutOrder
     list.Padding,list.Parent = UDim.new(0,3),frame
     local labels = {}
     for index, text in {string.rep("Wrapped text ",6),"Hello world"} do
      local label = Instance.new("TextLabel")
      label.Size,label.AutomaticSize = UDim2.fromOffset(0,0),Enum.AutomaticSize.Y
      label.FontFace,label.TextSize = Font.new("rbxasset://fonts/families/BuilderSans.json"),14
      label.Text,label.TextWrapped,label.LayoutOrder,label.Parent = text,true,index,frame
      local constraint = Instance.new("UISizeConstraint")
      constraint.MinSize = Vector2.new(1,1)
      constraint.MaxSize = if limited then Vector2.new(180,50) else Vector2.new(1000,1000)
      constraint.Parent = label
      labels[index]=label
     end
     task.wait(0.05)
     observationIndex += 1
     local observation = expected[observationIndex]
     for index, label in labels do
      local child = observation.children[index]
      assert(label.AbsoluteSize == Vector2.new(unpack(child.size)), "flexed text size " .. observationIndex .. "/" .. index .. ": " .. tostring(label.AbsoluteSize))
      assert(label.TextBounds == Vector2.new(unpack(child.bounds)), "flexed text bounds " .. observationIndex .. "/" .. index .. ": " .. tostring(label.TextBounds))
      assert(label.AbsolutePosition-frame.AbsolutePosition == Vector2.new(unpack(child.position)), "flexed text position " .. observationIndex .. "/" .. index)
      assert(label.TextFits == child.fits, "flexed text fits " .. observationIndex .. "/" .. index)
     end
     assert(list.AbsoluteContentSize == Vector2.new(unpack(observation.content)), "flexed text content " .. observationIndex .. ": " .. tostring(list.AbsoluteContentSize))
     frame:Destroy()
    end
   end
  end
 end
 screen:Destroy()

return true
]==]
