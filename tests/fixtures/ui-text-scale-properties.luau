--!strict

return [==[
for _,class in {"TextLabel","TextButton","TextBox"} do
 local object=Instance.new(class)
 local events={}
 local connection=object.Changed:Connect(function(name)
  if name=="TextScaled" or name=="TextWrapped" then
   table.insert(events,name.."/"..tostring(object.TextScaled).."/"..tostring(object.TextWrapped))
  end
 end)
 assert(not object.TextScaled and not object.TextWrapped)
 object.TextScaled=true
 assert(object.TextScaled and object.TextWrapped)
 assert(table.concat(events,"|")=="TextScaled/true/false|TextWrapped/true/true",class.." scaling order")
 table.clear(events)
 object.TextWrapped=false
 assert(not object.TextScaled and not object.TextWrapped)
 assert(table.concat(events,"|")=="TextWrapped/true/false|TextScaled/false/false",class.." unwrapping order")
 object.TextScaled=true
 table.clear(events)
 object.TextScaled=false
 assert(not object.TextScaled and object.TextWrapped)
 assert(table.concat(events,"|")=="TextScaled/false/true",class.." retains wrapping")
 connection:Disconnect()
 object:Destroy()
end
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
for _,class in {"TextLabel","TextButton","TextBox"} do
 local object=Instance.new(class)
 object.Size,object.Text,object.TextSize=UDim2.fromOffset(40,40),"+2",100
 object.TextScaled=true
 local constraint=Instance.new("UITextSizeConstraint")
 constraint.MaxTextSize,constraint.Parent=16,object
 object.Parent=screen
 task.wait(.05)
 assert(object.TextWrapped and object.TextScaled,class.." enables effective wrapping")
 assert(object.TextFits and object.TextBounds.X<=40 and object.TextBounds.Y<=24,class.." respects the text size constraint")
 object:Destroy()
end
screen:Destroy()
return true
]==]
