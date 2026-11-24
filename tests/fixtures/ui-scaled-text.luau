--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
for _, factor in { 0.5, 0.75, 1, 1.25, 1.5, 2 } do
 local frame = Instance.new("Frame")
 frame.Size, frame.Parent = UDim2.fromOffset(400, 200), screen
 local scale = Instance.new("UIScale")
 scale.Scale, scale.Parent = factor, frame
 local label = Instance.new("TextLabel")
 label.Text, label.FontFace = "99", Font.new("rbxasset://fonts/families/BuilderSans.json")
 label.TextScaled, label.Size = true, UDim2.fromOffset(40, 40)
 local constraint = Instance.new("UITextSizeConstraint")
 constraint.MaxTextSize, constraint.Parent = 16, label
 label.Parent = frame
 task.wait(0.1)
 assert(label.TextBounds.Y == 16 and label.TextBounds.X > 0 and label.TextBounds.X <= 16, `scale {factor}: {label.TextBounds}`)
 assert(label.AbsoluteSize == Vector2.new(40 * factor, 40 * factor), `scale {factor}: {label.AbsoluteSize}`)
 assert(label.TextFits, `scale {factor}: text must fit`)
 frame:Destroy()
end
screen:Destroy()
return true
]==]
