--!strict

return [==[
local input,gui=game.UserInputService,game.GuiService
local virtual=assert(input:CreateVirtualInput())
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local function button(name,x,y,w,h,parent)
 local object=Instance.new("TextButton")
 object.Name,object.Text,object.Position,object.Size,object.Parent=name,"",UDim2.fromOffset(x,y),UDim2.fromOffset(w,h),parent or screen
 return object
end
local function step(from,direction,expected)
 gui.SelectedObject=from
 task.wait(.05)
 local code=Enum.KeyCode[if input.PreferredInput==Enum.PreferredInput.Gamepad then (if direction=="Down" then "Three" else "Four") else direction]
 virtual:SendKey(true,code,false)
 task.wait(.05)
 virtual:SendKey(false,code,false)
 task.wait(.05)
 assert(gui.SelectedObject==expected,"directional rectangle overlap chooses "..expected.Name)
end
local first=button("Mute",180,100,60,44)
local wide=button("Brightness",100,160,400,44)
local last=button("Apply",180,220,60,44)
task.wait(.05)
step(first,"Down",wide)
for _,x in {0,60,100,160,210,240,250,300} do
 wide.Position=UDim2.fromOffset(x,160)
 step(first,"Down",if x<240 then wide else last)
end
wide:Destroy()
last:Destroy()
for _,distance in {100,120,160} do
 local near=button("Near",180,160,60,44)
 local far=button("Far",180,100+distance,60,44)
 for _,x in {80,120,125,160,180,220,235,240,300} do
  near.Position=UDim2.fromOffset(x,160)
  step(first,"Down",if x>120 and x<240 then near else far)
 end
 near:Destroy();far:Destroy()
end
first:Destroy()
local group=Instance.new("Frame")
group.Position,group.Size,group.SelectionGroup,group.Parent=UDim2.fromOffset(100,100),UDim2.fromOffset(300,100),true,screen
local field=button("Field",0,0,200,40,group)
local minus=button("Minus",210,0,30,40,group)
local nextField=button("Next",0,60,200,40,group)
local exit=button("Exit",0,240,50,40)
task.wait(.05)
step(field,"Right",minus)
step(nextField,"Down",exit)
group.SelectionBehaviorDown=Enum.SelectionBehavior.Stop
step(nextField,"Down",nextField)
gui.SelectedObject=nil
screen:Destroy()
return true
]==]
