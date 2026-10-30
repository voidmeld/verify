--!strict
return [==[
local u=game:GetService("UserInputService")
local v=u:CreateVirtualInput()
local trace={}
local connections={}
for _,event in {"InputBegan","InputChanged","InputEnded"} do
 table.insert(connections,u[event]:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.Gamepad1 then
   table.insert(trace,event.."/"..input.KeyCode.Name.."/"..input.UserInputState.Name.."/"..tostring(input.Position).."/"..tostring(input.Delta))
   local same=false
   for _,state in u:GetGamepadState(Enum.UserInputType.Gamepad1) do
    if state.KeyCode==input.KeyCode then same=state==input end
   end
   assert(same,"events use the gamepad state objects")
  else error("controller mode emitted "..input.UserInputType.Name) end
 end))
end
local steps={
 {"Nine",true,"InputBegan/ButtonA/Begin/0, 0, 1/0, 0, 1"},
 {"Nine",false,"InputEnded/ButtonA/End/0, 0, 0/0, 0, -1"},
 {"O",true,"InputBegan/ButtonR1/Begin/0, 0, 1/0, 0, 1"},
 {"O",false,"InputEnded/ButtonR1/End/0, 0, 0/0, 0, -1"},
 {"P",true,"InputChanged/ButtonR2/Change/0, 0, 1/0, 0, 1|InputBegan/ButtonR2/Begin/0, 0, 1/0, 0, 0"},
 {"P",false,"InputChanged/ButtonR2/Change/0, 0, 0/0, 0, -1|InputEnded/ButtonR2/End/0, 0, 0/0, 0, 0"},
 {"W",true,"InputChanged/Thumbstick1/Change/0, 1, 0/0, 1, 0"},
 {"D",true,"InputChanged/Thumbstick1/Change/1, 1, 0/1, 0, 0"},
 {"W",false,"InputChanged/Thumbstick1/Change/1, 0, 0/0, -1, 0"},
 {"D",false,"InputEnded/Thumbstick1/End/0, 0, 0/-1, 0, 0"},
 {"W",true,"InputChanged/Thumbstick1/Change/0, 1, 0/0, 1, 0"},
 {"S",true,"InputEnded/Thumbstick1/End/0, 0, 0/0, -1, 0"},
 {"S",false,"InputChanged/Thumbstick1/Change/0, 1, 0/0, 1, 0"},
 {"W",false,"InputEnded/Thumbstick1/End/0, 0, 0/0, -1, 0"},
 {"Z",true,""},{"Z",false,""},
 {"S",true,"InputChanged/Thumbstick1/Change/0, -1, 0/0, -1, 0"},
 {"S",true,"InputChanged/Thumbstick1/Change/0, -2, 0/0, -1, 0"},
 {"S",false,"InputChanged/Thumbstick1/Change/0, -1, 0/0, 1, 0"},
 {"W",true,"InputEnded/Thumbstick1/End/0, 0, 0/0, 1, 0"},
 {"W",false,"InputChanged/Thumbstick1/Change/0, -1, 0/0, -1, 0"},
}
for _,step in steps do
 table.clear(trace)
 v:SendKey(step[2],Enum.KeyCode[step[1]],false)
 game.RunService.RenderStepped:Wait()
 assert(table.concat(trace,"|")==step[3],step[1]..": "..table.concat(trace,"|"))
 assert(#u:GetKeysPressed()==0,"controller keys do not become held keyboard keys")
end
assert(u.GamepadEnabled and u:GetGamepadConnected(Enum.UserInputType.Gamepad1),"connected gamepad")
assert(#u:GetConnectedGamepads()==1,"one virtual controller")
assert(u:GetLastInputType()==Enum.UserInputType.Gamepad1,"last controller input")
for _,c in connections do c:Disconnect() end
v:SendKey(false,Enum.KeyCode.S,false)
return true
]==]
