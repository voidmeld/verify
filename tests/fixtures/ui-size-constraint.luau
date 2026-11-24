--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset, screen.Parent = true, game.Players.LocalPlayer.PlayerGui
local parent = Instance.new("Frame")
parent.Size, parent.Position, parent.Parent = UDim2.fromOffset(400, 200), UDim2.fromOffset(20, 30), screen
local expected = { RelativeXY = Vector2.new(210, 70), RelativeXX = Vector2.new(210, 120), RelativeYY = Vector2.new(110, 70) }
for name, size in expected do
 local child = Instance.new("Frame")
 child.SizeConstraint = Enum.SizeConstraint[name]
 child.Size, child.Position, child.Parent = UDim2.new(.5, 10, .25, 20), UDim2.fromScale(.25, .5), parent
 for _ = 1, 3 do game:GetService("RunService").RenderStepped:Wait() end
 assert(child.AbsoluteSize == size, name .. " size " .. tostring(child.AbsoluteSize))
 assert(child.AbsolutePosition - parent.AbsolutePosition == Vector2.new(100, 100), name .. " position")
 child:Destroy()
end
local child = Instance.new("Frame")
child.SizeConstraint = Enum.SizeConstraint.RelativeXX
child.Size, child.Parent = UDim2.new(.5, 10, .25, 20), parent
parent.Size = UDim2.fromOffset(300, 150)
for _ = 1, 3 do game:GetService("RunService").RenderStepped:Wait() end
assert(child.AbsoluteSize == Vector2.new(160, 95), "resized relative XX")
local scale = Instance.new("UIScale")
scale.Scale, scale.Parent = 2, parent
for _ = 1, 3 do game:GetService("RunService").RenderStepped:Wait() end
assert(child.AbsoluteSize == Vector2.new(320, 190), "scaled relative XX")
local limit = Instance.new("UISizeConstraint")
limit.MaxSize, limit.Parent = Vector2.new(140, 80), child
for _ = 1, 3 do game:GetService("RunService").RenderStepped:Wait() end
assert(child.AbsoluteSize == Vector2.new(280, 160), "limited relative XX")
screen:Destroy()
return true
]==]
