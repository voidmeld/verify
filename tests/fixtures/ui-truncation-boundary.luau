--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset = true
screen.Parent = game.Players.LocalPlayer.PlayerGui
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(256, 128)
frame.Parent = screen
local params = Instance.new("GetTextBoundsParams")
params.Font = Font.new("rbxasset://fonts/families/BuilderSans.json")
params.Size, params.Width = 14, 100000
local function measure(text)
	params.Text = text
	return game.TextService:GetTextBoundsAsync(params).X
end
local mark = measure("…")
local label = Instance.new("TextLabel")
label.FontFace, label.TextSize = params.Font, params.Size
label.Text = string.rep("A", 10)
label.Parent = frame
for _, mode in {Enum.TextTruncate.AtEnd, Enum.TextTruncate.SplitWord} do
	label.TextTruncate = mode
	for count = 1, 3 do
		local expected = measure(string.rep("A", count)) + mark
		local previous = measure(string.rep("A", count - 1)) + mark
		local threshold = math.ceil(expected)
		for _, delta in {-0.75, -0.25, 0, 0.25} do
			label.Size = UDim2.new((threshold + delta) / 256, 0, 0, 24)
			game.RunService.RenderStepped:Wait()
			local wanted = if threshold + delta < expected then previous else expected
			assert(math.abs(label.TextBounds.X - wanted) < 0.00001, mode.Name .. " boundary " .. count .. "/" .. delta .. ": " .. tostring(label.TextBounds))
			assert(not label.TextFits, "truncated text does not fit")
		end
	end
end
label:Destroy()
params:Destroy()
screen:Destroy()
return true
]==]
