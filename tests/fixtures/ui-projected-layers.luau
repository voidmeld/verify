--!strict

return [==[
local camera = workspace.CurrentCamera
local originalFrame, originalType, originalField = camera.CFrame, camera.CameraType, camera.FieldOfView
task.wait(2)
camera.CameraType, camera.FieldOfView = Enum.CameraType.Scriptable, 70
local mount = Instance.new("Folder", game.Players.LocalPlayer.PlayerGui)
local screen = Instance.new("ScreenGui", mount)
local frame = Instance.new("Frame", screen)
frame.Size, frame.Position, frame.Rotation = UDim2.fromOffset(300, 200), UDim2.fromOffset(100, 80), 30
local scale = Instance.new("UIScale", frame)
scale.Scale = 2
local part = Instance.new("Part", workspace)
part.Anchored, part.Size, part.CFrame = true, Vector3.new(4, 6, 2), CFrame.new(0, 5, 0)
local bill = Instance.new("BillboardGui", frame)
bill.Adornee, bill.Size = part, UDim2.new(4, 20, 2, 10)
local label = Instance.new("TextLabel", bill)
label.Size, label.Position = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.25, 0.25)
label.FontFace, label.TextSize, label.Text = Font.new("rbxasset://fonts/families/BuilderSans.json"), 14, "Hello"
local child = Instance.new("Frame", label)
child.Size, child.Position = UDim2.new(0.5, 3, 0.5, 2), UDim2.fromScale(0.5, 0.5)
local params = Instance.new("GetTextBoundsParams")
params.Font, params.Size, params.Text = label.FontFace, label.TextSize, label.Text
local bounds = game.TextService:GetTextBoundsAsync(params)
local function near(got, want, name)
 assert((got - want).Magnitude < 0.001, name .. ": " .. tostring(got) .. " expected " .. tostring(want))
end
local function check(depth)
 task.wait(0.1)
 local pixels = camera.ViewportSize.Y / (2 * math.tan(math.rad(35)) * depth)
 local size = Vector2.new(math.round(4 * pixels + 20), math.round(2 * pixels + 10))
 near(bill.AbsolutePosition, Vector2.zero, "projected canvas origin")
 near(bill.AbsoluteSize, size, "projected canvas size")
 near(label.AbsolutePosition, size * 0.25, "text position")
 near(label.AbsoluteSize, size * 0.5, "text size")
 near(label.TextBounds, bounds, "text bounds")
 near(child.AbsolutePosition, size * 0.5, "descendant position")
 near(child.AbsoluteSize, size * 0.25 + Vector2.new(3, 2), "descendant size")
 assert(label.TextFits, "projected text fits")
 assert(label.AbsoluteRotation == 0, "projection resets screen rotation")
end
for _, distance in {20, 40} do
 camera.CFrame = CFrame.new(0, 5, distance)
 check(distance)
 bill.SizeOffset = Vector2.new(0.25, -0.5)
 bill.StudsOffset, bill.ExtentsOffset = Vector3.new(1, 2, 3), Vector3.new(1, 1, 1)
 bill.AlwaysOnTop, bill.LightInfluence = true, 0.75
 check(distance - 4)
 bill.AlwaysOnTop, bill.LightInfluence = false, 0
 check(distance - 4)
 bill.StudsOffset, bill.ExtentsOffset = Vector3.zero, Vector3.zero
 check(distance)
end
local previous, previousText, previousChild = bill.AbsoluteSize, label.AbsoluteSize, child.AbsoluteSize
bill.Enabled = false
camera.CFrame = CFrame.new(0, 5, 20)
task.wait(0.1)
near(bill.AbsoluteSize, previous, "disabled canvas retains geometry")
near(label.AbsoluteSize, previousText, "disabled text retains geometry")
near(child.AbsoluteSize, previousChild, "disabled descendants retain geometry")
bill.Enabled = true
check(20)
bill.StudsOffset = Vector3.new(3, 4, 5)
bill.MaxDistance = 16
check(15)
bill.MaxDistance = 15
check(15)
bill.MaxDistance = 14
task.wait(0.1)
near(bill.AbsoluteSize, Vector2.zero, "range follows offset depth")
bill.StudsOffset = Vector3.zero
bill.MaxDistance = 10
task.wait(0.1)
near(bill.AbsoluteSize, Vector2.zero, "out of range canvas")
near(label.AbsoluteSize, Vector2.zero, "out of range text")
near(child.AbsoluteSize, Vector2.new(3, 2), "out of range authored offsets")
near(label.TextBounds, bounds, "out of range text bounds")
assert(not label.TextFits, "out of range text does not fit")
bill.MaxDistance = 20
check(20)
bill.MaxDistance = 0
camera.CFrame = CFrame.new(0, 5, 40)
check(40)
bill.Adornee, bill.Parent = nil, part
check(40)
part.CFrame = CFrame.new(0, 5, 10)
check(30)
camera.CFrame = CFrame.new(40, 5, 10) * CFrame.Angles(0, math.rad(90), 0)
bill.ExtentsOffset = Vector3.new(0, 0, 1)
check(38)
bill.ExtentsOffset = Vector3.zero
bill.StudsOffsetWorldSpace = Vector3.new(3, 0, 0)
check(37)
bill.StudsOffsetWorldSpace = Vector3.zero
camera.CFrame = CFrame.new(0, 5, -20)
task.wait(0.1)
near(bill.AbsoluteSize, Vector2.zero, "behind camera canvas")
near(label.AbsoluteSize, Vector2.zero, "behind camera text")
bill:Destroy()
part:Destroy()
mount:Destroy()
camera.CFrame, camera.CameraType, camera.FieldOfView = originalFrame, originalType, originalField
return true
]==]
