--!strict
return [==[
local input = game:GetService("UserInputService")
local virtual = assert(input:CreateVirtualInput())
local screen = Instance.new("ScreenGui")
screen.ScreenInsets = Enum.ScreenInsets.None
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = assert(game.Players.LocalPlayer).PlayerGui
local background = Instance.new("ScrollingFrame")
background.Size = UDim2.fromScale(1,1)
background.CanvasSize = UDim2.fromOffset(0,1200)
background.ScrollBarThickness = 0
background.Parent = screen
local button = Instance.new("TextButton")
button.Position, button.Size = UDim2.fromOffset(20,40), UDim2.fromOffset(120,44)
button.Parent = background
local clicks = 0
local connection = button.Activated:Connect(function() clicks += 1 end)
local function rest()
 for _ = 1, 40 do game.RunService.RenderStepped:Wait() end
end
for _, row in {
 {name="none", clicks=1, wheel=100, touch=180},
 {name="active Frame", class="Frame", active=true, clicks=0, wheel=100},
 {name="inactive Frame All", class="Frame", active=false, sink=true, clicks=1, wheel=100},
 {name="active Frame All", class="Frame", active=true, sink=true, clicks=0, wheel=100, touch=0},
 {name="scrolling shield", class="ScrollingFrame", active=true, clicks=0, wheel=0, touch=0},
} do
 local shield
 if row.class then
  shield = Instance.new(row.class)
  shield.Active, shield.Size, shield.BackgroundTransparency = row.active, UDim2.fromScale(1,1), 1
  shield.ZIndex = 10
  if row.sink then shield.InputSink = Enum.InputSink.All end
  if shield:IsA("ScrollingFrame") then
   shield.CanvasSize, shield.ScrollBarThickness = UDim2.new(), 0
  end
  shield.Parent = screen
 end
 background.CanvasPosition = Vector2.zero
 rest()
 local before = clicks
 local point = Vector2.new(40,60)
 virtual:SendMousePosition(point)
 virtual:SendMouseButton(point,Enum.UserInputType.MouseButton1,true)
 virtual:SendMouseButton(point,Enum.UserInputType.MouseButton1,false)
 assert(clicks-before == row.clicks,`{row.name}: clicks {clicks-before}`)
 virtual:SendPointerAction(Vector2.new(40,300),{Wheel=-1})
 rest()
 assert(math.abs(background.CanvasPosition.Y-row.wheel)<0.1,`{row.name}: wheel {background.CanvasPosition.Y}`)
 if row.touch ~= nil then
  game.StudioDeviceSimulatorService:SetDeviceAsync("iphone_14")
  game.StudioDeviceSimulatorService:SetOrientationAsync(Enum.ScreenOrientation.Portrait)
  background.CanvasPosition = Vector2.zero
  rest()
  local start, finish = Vector2.new(40,400), Vector2.new(40,220)
  virtual:SendMousePosition(start)
  virtual:SendMouseButton(start,Enum.UserInputType.MouseButton1,true)
  virtual:SendMousePosition(finish)
  virtual:SendMouseButton(finish,Enum.UserInputType.MouseButton1,false)
  rest()
  assert(math.abs(background.CanvasPosition.Y-row.touch)<0.1,`{row.name}: touch {background.CanvasPosition.Y}`)
  game.StudioDeviceSimulatorService:StopSimulationAsync()
  rest()
 end
 if shield then shield:Destroy() end
end
connection:Disconnect()
screen:Destroy()
return true
]==]
