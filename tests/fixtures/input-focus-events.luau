--!strict

return [==[
local screen = Instance.new("ScreenGui")
screen.Parent = game.Players.LocalPlayer.PlayerGui
local input = game.UserInputService
local a, b = Instance.new("TextBox"), Instance.new("TextBox")
a.Name, b.Name = "A", "B"
a.Size, b.Size = UDim2.fromOffset(100, 40), UDim2.fromOffset(100, 40)
b.Position = UDim2.fromOffset(0, 50)
a.Text, b.Text, a.Parent, b.Parent = "A text", "B text", screen, screen
local trace, phase = {}, "setup"
local function record(event, box, submitted)
 local current = input:GetFocusedTextBox()
 table.insert(trace, table.concat({phase, event, box.Name, if current then current.Name else "none", tostring(box:IsFocused()), tostring(submitted)}, "|"))
end
local connections = {
 input.TextBoxFocused:Connect(function(box) record("service focused", box) end),
 input.TextBoxFocusReleased:Connect(function(box) record("service released", box) end),
}
for _, box in {a, b} do
 table.insert(connections, box.Focused:Connect(function() record("box focused", box) end))
 table.insert(connections, box.FocusLost:Connect(function(submitted) record("box released", box, submitted) end))
end
task.wait(0.1)
for _, entry in {
 {"capture A", function() a:CaptureFocus() end},
 {"capture A again", function() a:CaptureFocus() end},
 {"capture B", function() b:CaptureFocus() end},
 {"release A", function() a:ReleaseFocus() end},
 {"submit B", function() b:ReleaseFocus(true) end},
 {"recapture A", function() a:CaptureFocus() end},
 {"destroy A", function() a:Destroy() end},
} do
 phase = entry[1]
 entry[2]()
 task.wait(0.1)
 local current = input:GetFocusedTextBox()
 table.insert(trace, phase .. "|after|" .. (if current then current.Name else "none"))
end
for _, connection in connections do connection:Disconnect() end
screen:Destroy()
local expected = {
 "capture A|box focused|A|A|true|nil",
 "capture A|service focused|A|A|true|nil",
 "capture A|after|A",
 "capture A again|after|A",
 "capture B|box released|A|A|true|false",
 "capture B|box focused|B|B|true|nil",
 "capture B|service focused|B|B|true|nil",
 "capture B|after|B",
 "release A|after|B",
 "submit B|box released|B|none|false|true",
 "submit B|service released|B|none|false|nil",
 "submit B|after|none",
 "recapture A|box focused|A|A|true|nil",
 "recapture A|service focused|A|A|true|nil",
 "recapture A|after|A",
 "destroy A|box released|A|none|false|false",
 "destroy A|service released|A|none|false|nil",
 "destroy A|after|none",
}
assert(table.concat(trace, "\n") == table.concat(expected, "\n"), table.concat(trace, "\n"))
return true
]==]
