--!strict

return [==[
 local screen = Instance.new("ScreenGui")
 screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
 local expected = game.HttpService:JSONDecode([=[[{"limits":[[0,0],[1000,1000]],"size":[120,0],"class":"Frame","wrapped":false,"axis":"X"},{"limits":[[80,40],[1000,1000]],"size":[120,40],"class":"Frame","wrapped":false,"axis":"X"},{"limits":[[0,0],[50,40]],"size":[120,0],"class":"Frame","wrapped":false,"axis":"X"},{"limits":[[80,40],[100,60]],"size":[120,40],"class":"Frame","wrapped":false,"axis":"X"},{"limits":[[0,0],[1000,1000]],"size":[100,80],"class":"Frame","wrapped":false,"axis":"Y"},{"limits":[[80,40],[1000,1000]],"size":[100,80],"class":"Frame","wrapped":false,"axis":"Y"},{"limits":[[0,0],[50,40]],"size":[50,80],"class":"Frame","wrapped":false,"axis":"Y"},{"limits":[[80,40],[100,60]],"size":[100,80],"class":"Frame","wrapped":false,"axis":"Y"},{"limits":[[0,0],[1000,1000]],"size":[120,80],"class":"Frame","wrapped":false,"axis":"XY"},{"limits":[[80,40],[1000,1000]],"size":[120,80],"class":"Frame","wrapped":false,"axis":"XY"},{"limits":[[0,0],[50,40]],"size":[120,80],"class":"Frame","wrapped":false,"axis":"XY"},{"limits":[[80,40],[100,60]],"size":[120,80],"class":"Frame","wrapped":false,"axis":"XY"},{"bounds":[450,14],"limits":[[0,0],[1000,1000]],"fits":false,"size":[450,0],"class":"TextLabel","wrapped":false,"axis":"X"},{"bounds":[450,14],"limits":[[0,0],[1000,1000]],"fits":false,"size":[450,0],"class":"TextLabel","wrapped":true,"axis":"X"},{"bounds":[450,14],"limits":[[80,40],[1000,1000]],"fits":true,"size":[450,40],"class":"TextLabel","wrapped":false,"axis":"X"},{"bounds":[450,14],"limits":[[80,40],[1000,1000]],"fits":true,"size":[450,40],"class":"TextLabel","wrapped":true,"axis":"X"},{"bounds":[450,14],"limits":[[0,0],[50,40]],"fits":false,"size":[50,0],"class":"TextLabel","wrapped":false,"axis":"X"},{"bounds":[48,14],"limits":[[0,0],[50,40]],"fits":false,"size":[50,0],"class":"TextLabel","wrapped":true,"axis":"X"},{"bounds":[450,14],"limits":[[80,40],[100,60]],"fits":false,"size":[100,40],"class":"TextLabel","wrapped":false,"axis":"X"},{"bounds":[75,28],"limits":[[80,40],[100,60]],"fits":false,"size":[100,40],"class":"TextLabel","wrapped":true,"axis":"X"},{"bounds":[450,14],"limits":[[0,0],[1000,1000]],"fits":false,"size":[100,14],"class":"TextLabel","wrapped":false,"axis":"Y"},{"bounds":[75,84],"limits":[[0,0],[1000,1000]],"fits":true,"size":[100,84],"class":"TextLabel","wrapped":true,"axis":"Y"},{"bounds":[450,14],"limits":[[80,40],[1000,1000]],"fits":false,"size":[100,40],"class":"TextLabel","wrapped":false,"axis":"Y"},{"bounds":[75,84],"limits":[[80,40],[1000,1000]],"fits":true,"size":[100,84],"class":"TextLabel","wrapped":true,"axis":"Y"},{"bounds":[450,14],"limits":[[0,0],[50,40]],"fits":false,"size":[50,14],"class":"TextLabel","wrapped":false,"axis":"Y"},{"bounds":[48,28],"limits":[[0,0],[50,40]],"fits":false,"size":[50,28],"class":"TextLabel","wrapped":true,"axis":"Y"},{"bounds":[450,14],"limits":[[80,40],[100,60]],"fits":false,"size":[100,40],"class":"TextLabel","wrapped":false,"axis":"Y"},{"bounds":[75,56],"limits":[[80,40],[100,60]],"fits":false,"size":[100,56],"class":"TextLabel","wrapped":true,"axis":"Y"},{"bounds":[450,14],"limits":[[0,0],[1000,1000]],"fits":true,"size":[450,14],"class":"TextLabel","wrapped":false,"axis":"XY"},{"bounds":[450,14],"limits":[[0,0],[1000,1000]],"fits":true,"size":[450,14],"class":"TextLabel","wrapped":true,"axis":"XY"},{"bounds":[450,14],"limits":[[80,40],[1000,1000]],"fits":true,"size":[450,40],"class":"TextLabel","wrapped":false,"axis":"XY"},{"bounds":[450,14],"limits":[[80,40],[1000,1000]],"fits":true,"size":[450,40],"class":"TextLabel","wrapped":true,"axis":"XY"},{"bounds":[450,14],"limits":[[0,0],[50,40]],"fits":false,"size":[50,14],"class":"TextLabel","wrapped":false,"axis":"XY"},{"bounds":[48,28],"limits":[[0,0],[50,40]],"fits":false,"size":[50,28],"class":"TextLabel","wrapped":true,"axis":"XY"},{"bounds":[450,14],"limits":[[80,40],[100,60]],"fits":false,"size":[100,40],"class":"TextLabel","wrapped":false,"axis":"XY"},{"bounds":[75,56],"limits":[[80,40],[100,60]],"fits":false,"size":[100,56],"class":"TextLabel","wrapped":true,"axis":"XY"}]]=])
 local index = 0
 for _, class in {"Frame", "TextLabel"} do
  for _, axis in {"X", "Y", "XY"} do
   for _, limits in {{{0,0},{1000,1000}}, {{80,40},{1000,1000}}, {{0,0},{50,40}}, {{80,40},{100,60}}} do
    for _, wrapped in {false, true} do
     if class == "Frame" and wrapped then continue end
     local object = Instance.new(class)
     object.Size, object.AutomaticSize = UDim2.fromOffset(100, 0), Enum.AutomaticSize[axis]
     object.Parent = screen
     if class == "Frame" then
      local child = Instance.new("Frame")
      child.Size, child.Parent = UDim2.fromOffset(120,80), object
     else
      object.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json")
      object.TextSize, object.TextWrapped = 14, wrapped
      object.Text = string.rep("Wrapped text ", 6)
     end
     local constraint = Instance.new("UISizeConstraint")
     constraint.MinSize, constraint.MaxSize = Vector2.new(unpack(limits[1])), Vector2.new(unpack(limits[2]))
     constraint.Parent = object
     task.wait(0.05)
     index += 1
     local observation = expected[index]
     assert(object.AbsoluteSize == Vector2.new(unpack(observation.size)), "automatic constraint size " .. index .. ": " .. tostring(object.AbsoluteSize))
     if class == "TextLabel" then
      assert(object.TextBounds == Vector2.new(unpack(observation.bounds)), "automatic constraint bounds " .. index .. ": " .. tostring(object.TextBounds))
      assert(object.TextFits == observation.fits, "automatic constraint fits " .. index)
     end
     object:Destroy()
    end
   end
  end
 end
 screen:Destroy()

return true
]==]
