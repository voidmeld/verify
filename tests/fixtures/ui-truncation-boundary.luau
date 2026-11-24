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
local count = 10
local natural = measure(string.rep("A", count))
local candidates = {}
for kept = 0, count do
	table.insert(candidates, measure(string.rep("A", kept)) + mark)
end
table.insert(candidates, natural)
local label = Instance.new("TextLabel")
label.FontFace, label.TextSize = params.Font, params.Size
label.Text = string.rep("A", count)
label.Parent = frame
for _, mode in {Enum.TextTruncate.AtEnd, Enum.TextTruncate.SplitWord} do
	label.TextTruncate = mode
	local previous = -1
	for step = 0, 33 do
		local width = (natural + 2) * step / 33
		label.Size = UDim2.new(width / 256, 0, 0, 24)
		game.RunService.RenderStepped:Wait()
		local tag = mode.Name .. " " .. tostring(width) .. ": " .. tostring(label.TextBounds)
		local bounds = label.TextBounds.X
		assert(bounds <= width + 0.001, "truncated text stays inside the width " .. tag)
		assert(bounds >= previous - 0.001, "bounds grow with the width " .. tag)
		previous = bounds
		if width >= natural + 0.001 then
			assert(math.abs(bounds - natural) < 0.001 and label.TextFits, "roomy text is untouched " .. tag)
		elseif width < natural - 1 then
			assert(bounds < natural and not label.TextFits, "narrow text is truncated " .. tag)
			local nearest = math.huge
			for _, candidate in candidates do
				nearest = math.min(nearest, math.abs(candidate - bounds))
			end
			assert(nearest <= 1 or bounds == 0, "bounds are a kept prefix plus the ellipsis " .. tag)
		end
	end
end
label.TextSize, label.Text = 16, "Automatic transmission mode"
label.TextTruncate = Enum.TextTruncate.AtEnd
params.Size = 16
local whole = measure(label.Text)
local last = 0
for _, width in {60, 100, 140} do
	label.Size = UDim2.fromOffset(width, 24)
	game.RunService.RenderStepped:Wait()
	local bounds = label.TextBounds.X
	assert(bounds <= width + 0.001 and bounds >= last - 0.001, "word boundary stays inside the width " .. width .. ": " .. tostring(label.TextBounds))
	assert(bounds < whole and not label.TextFits, "word boundary overflow " .. width)
	last = bounds
end
label:Destroy()
params:Destroy()
screen:Destroy()
return true
]==]
