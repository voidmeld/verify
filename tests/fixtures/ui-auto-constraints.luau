--!strict

return [==[
 local screen = Instance.new("ScreenGui")
 screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
 local expected = game.HttpService:JSONDecode([=[[{"limits":[[0,0],[1000,1000]],"axis":"X","class":"Frame","wrapped":false,"size":[120,0]},{"limits":[[80,40],[1000,1000]],"axis":"X","class":"Frame","wrapped":false,"size":[120,40]},{"limits":[[0,0],[50,40]],"axis":"X","class":"Frame","wrapped":false,"size":[120,0]},{"limits":[[80,40],[100,60]],"axis":"X","class":"Frame","wrapped":false,"size":[120,40]},{"limits":[[0,0],[1000,1000]],"axis":"Y","class":"Frame","wrapped":false,"size":[100,80]},{"limits":[[80,40],[1000,1000]],"axis":"Y","class":"Frame","wrapped":false,"size":[100,80]},{"limits":[[0,0],[50,40]],"axis":"Y","class":"Frame","wrapped":false,"size":[50,80]},{"limits":[[80,40],[100,60]],"axis":"Y","class":"Frame","wrapped":false,"size":[100,80]},{"limits":[[0,0],[1000,1000]],"axis":"XY","class":"Frame","wrapped":false,"size":[120,80]},{"limits":[[80,40],[1000,1000]],"axis":"XY","class":"Frame","wrapped":false,"size":[120,80]},{"limits":[[0,0],[50,40]],"axis":"XY","class":"Frame","wrapped":false,"size":[120,80]},{"limits":[[80,40],[100,60]],"axis":"XY","class":"Frame","wrapped":false,"size":[120,80]},{"bounds":[440,14],"limits":[[0,0],[1000,1000]],"axis":"X","wrapped":false,"fits":false,"class":"TextLabel","size":[440,0]},{"bounds":[440,14],"limits":[[0,0],[1000,1000]],"axis":"X","wrapped":true,"fits":false,"class":"TextLabel","size":[440,0]},{"bounds":[440,14],"limits":[[80,40],[1000,1000]],"axis":"X","wrapped":false,"fits":true,"class":"TextLabel","size":[440,40]},{"bounds":[440,14],"limits":[[80,40],[1000,1000]],"axis":"X","wrapped":true,"fits":true,"class":"TextLabel","size":[440,40]},{"bounds":[440,14],"limits":[[0,0],[50,40]],"axis":"X","wrapped":false,"fits":false,"class":"TextLabel","size":[50,0]},{"bounds":[46.66666793823242,14],"limits":[[0,0],[50,40]],"axis":"X","wrapped":true,"fits":false,"class":"TextLabel","size":[50,0]},{"bounds":[440,14],"limits":[[80,40],[100,60]],"axis":"X","wrapped":false,"fits":false,"class":"TextLabel","size":[100,40]},{"bounds":[73.33333587646485,28],"limits":[[80,40],[100,60]],"axis":"X","wrapped":true,"fits":false,"class":"TextLabel","size":[100,40]},{"bounds":[440,14],"limits":[[0,0],[1000,1000]],"axis":"Y","wrapped":false,"fits":false,"class":"TextLabel","size":[100,14]},{"bounds":[73.33333587646485,84],"limits":[[0,0],[1000,1000]],"axis":"Y","wrapped":true,"fits":true,"class":"TextLabel","size":[100,84]},{"bounds":[440,14],"limits":[[80,40],[1000,1000]],"axis":"Y","wrapped":false,"fits":false,"class":"TextLabel","size":[100,40]},{"bounds":[73.33333587646485,84],"limits":[[80,40],[1000,1000]],"axis":"Y","wrapped":true,"fits":true,"class":"TextLabel","size":[100,84]},{"bounds":[440,14],"limits":[[0,0],[50,40]],"axis":"Y","wrapped":false,"fits":false,"class":"TextLabel","size":[50,14]},{"bounds":[46.66666793823242,28],"limits":[[0,0],[50,40]],"axis":"Y","wrapped":true,"fits":false,"class":"TextLabel","size":[50,28]},{"bounds":[440,14],"limits":[[80,40],[100,60]],"axis":"Y","wrapped":false,"fits":false,"class":"TextLabel","size":[100,40]},{"bounds":[73.33333587646485,56],"limits":[[80,40],[100,60]],"axis":"Y","wrapped":true,"fits":false,"class":"TextLabel","size":[100,56]},{"bounds":[440,14],"limits":[[0,0],[1000,1000]],"axis":"XY","wrapped":false,"fits":true,"class":"TextLabel","size":[440,14]},{"bounds":[440,14],"limits":[[0,0],[1000,1000]],"axis":"XY","wrapped":true,"fits":true,"class":"TextLabel","size":[440,14]},{"bounds":[440,14],"limits":[[80,40],[1000,1000]],"axis":"XY","wrapped":false,"fits":true,"class":"TextLabel","size":[440,40]},{"bounds":[440,14],"limits":[[80,40],[1000,1000]],"axis":"XY","wrapped":true,"fits":true,"class":"TextLabel","size":[440,40]},{"bounds":[440,14],"limits":[[0,0],[50,40]],"axis":"XY","wrapped":false,"fits":false,"class":"TextLabel","size":[50,14]},{"bounds":[46.66666793823242,28],"limits":[[0,0],[50,40]],"axis":"XY","wrapped":true,"fits":false,"class":"TextLabel","size":[50,28]},{"bounds":[440,14],"limits":[[80,40],[100,60]],"axis":"XY","wrapped":false,"fits":false,"class":"TextLabel","size":[100,40]},{"bounds":[73.33333587646485,56],"limits":[[80,40],[100,60]],"axis":"XY","wrapped":true,"fits":false,"class":"TextLabel","size":[100,56]}]]=])
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
