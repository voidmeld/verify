--!strict
return [==[
local input = game:GetService("UserInputService")
local virtual = assert(input:CreateVirtualInput())
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, assert(game.Players.LocalPlayer).PlayerGui
local outer = Instance.new("ScrollingFrame")
outer.Position, outer.Size = UDim2.fromOffset(100,100), UDim2.fromOffset(400,400)
outer.CanvasSize, outer.Parent = UDim2.fromOffset(800,800), screen
local inner = Instance.new("ScrollingFrame")
inner.Size, inner.CanvasSize = UDim2.fromOffset(300,300), UDim2.fromOffset(600,600)
inner.Parent = outer
local target = Instance.new("Frame")
target.Size, target.Parent = UDim2.fromOffset(280,280), inner
local detector = Instance.new("UIDragDetector")
detector.Parent = target
local events, drags = {}, 0
local inset = game.GuiService:GetGuiInset()
local connections = {
 inner.InputChanged:Connect(function(object)
  if object.UserInputType == Enum.UserInputType.MouseWheel then table.insert(events,"inner") end
 end),
 input.InputChanged:Connect(function(object, processed)
  if object.UserInputType ~= Enum.UserInputType.MouseWheel then return end
  assert(object.UserInputState == Enum.UserInputState.Change and object.Delta == Vector3.zero)
  assert(object.Position.X == 250-inset.X and object.Position.Y == 250-inset.Y)
  table.insert(events,"service/"..tostring(processed))
 end),
 input.PointerAction:Connect(function(wheel, pan, pinch, processed)
  table.insert(events,`pointer/{wheel}/{pan.X}/{pan.Y}/{pinch}/{processed}`)
 end),
 detector.DragStart:Connect(function() drags += 1 end),
 detector.DragContinue:Connect(function() drags += 1 end),
 detector.DragEnd:Connect(function() drags += 1 end),
}
local function rest()
 for _ = 1, 40 do game.RunService.RenderStepped:Wait() end
end
local function reset()
 inner.CanvasPosition, outer.CanvasPosition = Vector2.new(100,100), Vector2.new(100,100)
 rest()
 table.clear(events)
end
reset()
virtual:SendPointerAction(Vector2.new(250,250), {})
virtual:SendPointerAction(Vector2.new(250,250), {Wheel=0, Pan=Vector2.zero, Pinch=0})
assert(#events == 0)
virtual:SendPointerAction(Vector2.new(250,250), {Wheel=-1})
for frame, expected in {100,108.2,124.3,141.5,156.2,168.3} do
 game.RunService.RenderStepped:Wait()
 assert(math.abs(inner.CanvasPosition.Y-expected)<1,`frame {frame}: {inner.CanvasPosition.Y}`)
end
rest()
assert(math.abs(inner.CanvasPosition.Y-200)<0.1 and outer.CanvasPosition == Vector2.new(100,100))
assert(table.concat(events,"|") == "inner|service/true|pointer/-1/0/0/0/true",table.concat(events,"|"))
reset()
inner.ScrollingEnabled = false
virtual:SendPointerAction(Vector2.new(250,250), {Wheel=-1})
rest()
assert(inner.CanvasPosition == Vector2.new(100,100) and math.abs(outer.CanvasPosition.Y-200)<0.1)
inner.ScrollingEnabled = true
reset()
inner.ScrollingDirection = Enum.ScrollingDirection.X
virtual:SendPointerAction(Vector2.new(250,250), {Pan=Vector2.new(30,30)})
rest()
assert(inner.CanvasPosition.X < 0.1 and inner.CanvasPosition.Y == 100)
assert(outer.CanvasPosition.X == 100 and outer.CanvasPosition.Y < 0.1)
assert(events[#events] == "pointer/0/75/75/0/true")
inner.ScrollingDirection = Enum.ScrollingDirection.XY
reset()
virtual:SendPointerAction(Vector2.new(250,250), {Pinch=0.1})
rest()
assert(math.abs(inner.CanvasPosition.Y-90)<0.1 and outer.CanvasPosition == Vector2.new(100,100))
assert(drags == 0,"pointer actions never start a drag detector")
reset()
assert(not pcall(function() virtual:SendPointerAction(Vector2.new(250,250), {Wheel=-3}) end))
assert(inner.CanvasPosition == Vector2.new(100,100))
virtual:SendPointerAction(Vector2.new(250,250), {Wheel=1})
inner:Destroy()
rest()
for _, connection in connections do connection:Disconnect() end
screen:Destroy()
return true
]==]
