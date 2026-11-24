--!strict
return [==[
local simulator=game:GetService("StudioDeviceSimulatorService")
simulator:SetDeviceAsync("iphone_14")
simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
task.wait(1)
local input=game:GetService("UserInputService")
local virtual=input:CreateVirtualInput()
local screen=Instance.new("ScreenGui")
screen.Name="TouchProbe"
screen.Parent=game.Players.LocalPlayer.PlayerGui
local button=Instance.new("TextButton")
button.Name,button.Text="Target",""
button.Position,button.Size=UDim2.fromOffset(50,30),UDim2.fromOffset(250,200)
button.Parent=screen
local rows,connections,objects={},{},{}
local function record(name,object,processed)
 local id=table.find(objects,object)
 if not id then table.insert(objects,object);id=#objects end
 table.insert(rows,{name=name,id=id,input=tostring(object.UserInputType),key=tostring(object.KeyCode),state=tostring(object.UserInputState),position={object.Position.X,object.Position.Y,object.Position.Z},delta={object.Delta.X,object.Delta.Y,object.Delta.Z},processed=processed})
end
for _,name in {"InputBegan","InputChanged","InputEnded","TouchStarted","TouchMoved","TouchEnded"} do
 table.insert(connections,input[name]:Connect(function(object,processed) record("service."..name,object,processed) end))
end
for _,name in {"InputBegan","InputChanged","InputEnded"} do
 table.insert(connections,button[name]:Connect(function(object) record("button."..name,object) end))
end
table.insert(connections,button.Activated:Connect(function(object,count) record("button.Activated",object,count) end))
for _,name in {"MouseEnter","MouseLeave","MouseButton1Down","MouseButton1Up","MouseButton1Click"} do
 table.insert(connections,button[name]:Connect(function() table.insert(rows,{name="button."..name}) end))
end
local inset=game.GuiService:GetGuiInset()
local function move(x,y)
 virtual:SendMousePosition(Vector2.new(x,y)+inset)
 task.wait(.1)
end
local function press(down,x,y)
 virtual:SendMouseButton(Vector2.new(x,y)+inset,Enum.UserInputType.MouseButton1,down)
 task.wait(.1)
end
task.wait(.2)
move(120,140)
table.insert(rows,{name="down"})
press(true,120,140)
table.insert(rows,{name="move-inside"})
move(150,150)
table.insert(rows,{name="move-outside"})
move(320,300)
table.insert(rows,{name="up-outside"})
press(false,320,300)
table.insert(rows,{name="tap"})
move(120,140)
press(true,120,140)
press(false,120,140)
table.insert(rows,{name="second-tap"})
press(true,120,140)
move(120,140)
press(false,120,140)
for _,connection in connections do connection:Disconnect() end
screen:Destroy()
local expected=game.HttpService:JSONDecode([=[[{"name":"down"},{"name":"button.MouseButton1Down"},{"name":"button.MouseEnter"},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"button.InputBegan","position":[120,93,0],"id":1,"key":"Enum.KeyCode.None","delta":[0,0,0]},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.InputBegan","position":[120,93,0],"id":1,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.TouchStarted","position":[120,93,0],"id":1,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"name":"move-inside"},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"button.InputChanged","position":[150,103,0],"id":1,"key":"Enum.KeyCode.None","delta":[30,10,0]},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"service.InputChanged","position":[150,103,0],"id":1,"key":"Enum.KeyCode.None","delta":[30,10,0],"processed":true},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"service.TouchMoved","position":[150,103,0],"id":1,"key":"Enum.KeyCode.None","delta":[30,10,0],"processed":true},{"name":"move-outside"},{"name":"button.MouseLeave"},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"button.InputEnded","position":[320,253,0],"id":1,"key":"Enum.KeyCode.None","delta":[170,150,0]},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"service.InputChanged","position":[320,253,0],"id":1,"key":"Enum.KeyCode.None","delta":[170,150,0],"processed":false},{"state":"Enum.UserInputState.Change","input":"Enum.UserInputType.Touch","name":"service.TouchMoved","position":[320,253,0],"id":1,"key":"Enum.KeyCode.None","delta":[170,150,0],"processed":false},{"name":"up-outside"},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.InputEnded","position":[320,253,0],"id":1,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":false},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.TouchEnded","position":[320,253,0],"id":1,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":false},{"name":"tap"},{"name":"button.MouseButton1Down"},{"name":"button.MouseEnter"},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"button.InputBegan","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0]},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.InputBegan","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.TouchStarted","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"name":"button.MouseButton1Up"},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"button.Activated","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":0},{"name":"button.MouseButton1Click"},{"name":"button.MouseLeave"},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"button.InputEnded","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0]},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.InputEnded","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.TouchEnded","position":[120,93,0],"id":2,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"name":"second-tap"},{"name":"button.MouseButton1Down"},{"name":"button.MouseEnter"},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"button.InputBegan","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0]},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.InputBegan","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"state":"Enum.UserInputState.Begin","input":"Enum.UserInputType.Touch","name":"service.TouchStarted","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"name":"button.MouseButton1Up"},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"button.Activated","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":1},{"name":"button.MouseButton1Click"},{"name":"button.MouseLeave"},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"button.InputEnded","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0]},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.InputEnded","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true},{"state":"Enum.UserInputState.End","input":"Enum.UserInputType.Touch","name":"service.TouchEnded","position":[120,93,0],"id":3,"key":"Enum.KeyCode.None","delta":[0,0,0],"processed":true}]]=])
assert(#rows==#expected, `touch event count {#rows} expected {#expected}`)
for index,want in expected do
 local got=rows[index]
 for _,key in {"name","id","input","state","key","processed"} do
  assert(got[key]==want[key], `touch event {index} {key}: {tostring(got[key])} expected {tostring(want[key])}`)
 end
 for _,key in {"position","delta","offset"} do
  local actual,required=got[key],want[key]
  assert((actual~=nil)==(required~=nil), `touch event {index} {key} presence`)
  if required then
   assert(#actual==#required)
   for part,value in required do assert(actual[part]==value, `touch event {index} {key}[{part}]: {actual[part]} expected {value}`) end
  end
 end
end
simulator:StopSimulationAsync()
return true
]==]
