--!strict

return [==[
local frame = Instance.new("Frame")
local tween = game:GetService("TweenService"):Create(frame, TweenInfo.new(1, Enum.EasingStyle.Linear), {
    Position = UDim2.fromOffset(100, 200),
    BackgroundTransparency = 1,
})
local ok, failure = pcall(function()
    tween:Play()
    task.wait(0.2)
    tween:Pause()
    local held = frame.Position
    local alpha = frame.BackgroundTransparency
    assert(alpha > 0 and alpha < 1, "numeric property must interpolate before completion")
    assert(math.abs(held.X.Offset - alpha * 100) <= 1, "position and numeric property must share progress")
    task.wait(0.1)
    assert(frame.Position == held, "pause must hold the intermediate position")
    tween:Play()
    task.wait(1)
    assert(frame.Position == UDim2.fromOffset(100, 200), "resuming must reach the exact target")
    frame.Position = UDim2.fromOffset(0, 0)
    frame.BackgroundTransparency = 0
    tween:Play()
    task.wait(0.2)
    tween:Cancel()
    held = frame.Position
    task.wait(0.1)
    assert(frame.Position == held, "cancellation must preserve the intermediate position")
end)
tween:Destroy()
frame:Destroy()
assert(ok, failure)
return true
]==]
