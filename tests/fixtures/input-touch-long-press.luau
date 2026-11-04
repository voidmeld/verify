--!strict

return [==[
local simulator=game.StudioDeviceSimulatorService
simulator:SetDeviceAsync("iphone_14")
simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
task.wait(.5)
local input=game.UserInputService
local virtual=assert(input:CreateVirtualInput())
local screen=Instance.new("ScreenGui")
screen.Parent=game.Players.LocalPlayer.PlayerGui
local target=Instance.new("TextButton")
target.Position,target.Size,target.Text,target.Parent=UDim2.fromOffset(50,30),UDim2.fromOffset(250,200),"",screen
local rows={}
local coordinateFailures={}
local raw,contact
local function point(value) return Vector2.new(value.X,value.Y) end
local inset=game.GuiService:GetGuiInset()
local connections={
 input.TouchStarted:Connect(function(value) contact=value end),
 target.TouchLongPress:Connect(function(positions,state)
  local expected=point(contact.Position)+inset
  if #positions~=1 or positions[1]~=expected then table.insert(coordinateFailures,"GUI "..tostring(positions[1]).." expected "..tostring(expected)) end
  table.insert(rows,"target/"..state.Name)
 end),
 input.TouchLongPress:Connect(function(positions,state,processed)
  if #positions~=1 or positions[1]~=point(contact.Position) then table.insert(coordinateFailures,"service input coordinates") end
  if not processed then table.insert(coordinateFailures,"unprocessed button long press") end
  table.insert(rows,"service/"..state.Name)
 end),
}
local base=target.AbsolutePosition+target.AbsoluteSize/2-game.GuiService:GetInsetArea(Enum.ScreenInsets.None).Min
for _,delta in {Vector2.new(0,0),Vector2.new(4,0),Vector2.new(3,3),Vector2.new(3,4),Vector2.new(5,0)} do
 table.clear(rows)
 raw=base
 virtual:SendMousePosition(raw)
 task.wait(.05)
 virtual:SendMouseButton(raw,Enum.UserInputType.MouseButton1,true,0)
 task.wait(.2)
 assert(#rows==0,"long press waits beyond touch down")
 raw+=delta
 virtual:SendMousePosition(raw)
 task.wait(.6)
 assert(#coordinateFailures==0,table.concat(coordinateFailures,"|"))
 if delta.Magnitude<5 then
  assert(table.concat(rows,"|")=="target/Begin|service/Begin","stationary touch begins once "..tostring(delta)..": "..table.concat(rows,"|"))
  raw+=Vector2.new(0,8)
  virtual:SendMousePosition(raw)
  task.wait(.05)
  assert(table.concat(rows,"|")=="target/Begin|service/Begin|target/Change|service/Change","recognized long press follows motion")
 else
  assert(#rows==0,"early movement cancels recognition")
 end
 virtual:SendMouseButton(raw,Enum.UserInputType.MouseButton1,false,0)
 task.wait(.05)
 if delta.Magnitude<5 then
  assert(table.concat(rows,"|")=="target/Begin|service/Begin|target/Change|service/Change|target/End|service/End","long press ends once")
 else assert(#rows==0,"cancelled touch emits no long press") end
end
table.clear(rows)
raw=base
virtual:SendMousePosition(raw)
task.wait(.05)
virtual:SendMouseButton(raw,Enum.UserInputType.MouseButton1,true,0)
task.wait(.1)
virtual:SendMouseButton(raw,Enum.UserInputType.MouseButton1,false,0)
task.wait(.6)
assert(#rows==0,"released touch cannot start a delayed long press")
assert(#coordinateFailures==0,table.concat(coordinateFailures,"|"))
for _,connection in connections do connection:Disconnect() end
screen:Destroy()
simulator:StopSimulationAsync()
return true
]==]
