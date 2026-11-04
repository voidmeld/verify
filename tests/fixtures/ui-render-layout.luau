--!strict

return [==[
local screen=Instance.new("ScreenGui")
screen.IgnoreGuiInset,screen.Parent=true,game.Players.LocalPlayer.PlayerGui
for _,phase in {"PreRender","RenderStepped"} do
 for _,kind in {"position","size","padding","constraint"} do
  local parent=Instance.new("Frame")
  parent.Position,parent.Size,parent.Parent=UDim2.fromOffset(10,20),UDim2.fromOffset(300,200),screen
  local frame=Instance.new("Frame")
  frame.Size,frame.Parent=UDim2.fromScale(1,1),parent
  local padding=Instance.new("UIPadding")
  padding.Parent=parent
  local constraint=Instance.new("UISizeConstraint")
  constraint.Parent=frame
  local list=Instance.new("UIListLayout")
  list.Parent=parent
  task.wait(.05)
  local origin=parent.AbsolutePosition
  local expectedPosition,expectedSize=origin,Vector2.new(300,200)
  if kind=="position" then expectedPosition+=Vector2.new(44,24)
  elseif kind=="size" then expectedSize=Vector2.new(280,170)
  elseif kind=="padding" then expectedPosition+=Vector2.new(12,8);expectedSize=Vector2.new(288,192)
  else expectedSize=Vector2.new(100,100) end
  local function check()
   assert(frame.AbsolutePosition==expectedPosition,phase.."/"..kind.." position")
   assert(frame.AbsoluteSize==expectedSize,phase.."/"..kind.." size")
   assert(list.AbsoluteContentSize==expectedSize,phase.."/"..kind.." content")
  end
  local complete=false
  local connection
  connection=game.RunService[phase]:Connect(function()
   connection:Disconnect()
   if kind=="position" then parent.Position+=UDim2.fromOffset(44,24)
   elseif kind=="size" then parent.Size=UDim2.fromOffset(280,170)
   elseif kind=="padding" then padding.PaddingLeft=UDim.new(0,12);padding.PaddingTop=UDim.new(0,8)
   else constraint.MaxSize=Vector2.new(100,100) end
   check()
   task.defer(function() check();complete=true end)
  end)
  repeat task.wait() until complete
  check()
  parent:Destroy()
 end
end
screen:Destroy()
return true
]==]
