--!strict
return [==[
local playerGui=game.Players.LocalPlayer.PlayerGui
local screen=Instance.new("ScreenGui")
screen.Parent=playerGui
local ancestor=Instance.new("Frame")
ancestor.Position=UDim2.fromOffset(100,100)
ancestor.Size=UDim2.fromOffset(400,400)
ancestor.Parent=screen
local parent=Instance.new("Frame")
parent.Position=UDim2.fromOffset(50,50)
parent.Size=UDim2.fromOffset(100,100)
parent.Parent=ancestor
local child=Instance.new("Frame")
child.Position=UDim2.fromOffset(120,20)
child.Size=UDim2.fromOffset(40,40)
child.Parent=parent
for _,outer in {0,90,0} do
 for _,inner in {0,90,0} do
  for _,own in {0,45} do
   for _,clip in {false,true} do
    ancestor.Rotation,parent.Rotation,child.Rotation=outer,inner,own
    parent.ClipsDescendants=clip
    game.RunService.RenderStepped:Wait()
    game.RunService.RenderStepped:Wait()
    local point=child.AbsolutePosition+child.AbsoluteSize/2
    local hit=table.find(playerGui:GetGuiObjectsAtPosition(point.X,point.Y),child)~=nil
    local expected=not clip or outer~=0 or inner~=0
    assert(hit==expected,"rotated clip "..outer.."/"..inner.."/"..own.."/"..tostring(clip))
   end
  end
 end
end
screen:Destroy()
return true
]==]
