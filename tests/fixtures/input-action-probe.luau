--!strict

return [==[
local context = Instance.new("InputContext")
context.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
local action = Instance.new("InputAction")
local log = {}
local function note(label) table.insert(log, label .. ":" .. tostring(action:GetState())) end
for _, name in { "Pressed", "Released", "StateChanged" } do
	action[name]:Connect(function(value)
		table.insert(log, name .. ":" .. tostring(value) .. ":" .. tostring(action:GetState()))
	end)
end
local function step(label, run)
	run()
	task.wait()
	note(label)
end
note("initial")
step("unparented", function() action:Fire(true) end)
step("parented", function() action.Parent = context end)
step("false", function() action:Fire(false) end)
step("true", function() action:Fire(true) end)
step("duplicate", function() action:Fire(true) end)
step("disable-action", function() action.Enabled = false end)
step("disabled-fire", function() action:Fire(true) end)
step("enable-action", function() action.Enabled = true end)
step("true-again", function() action:Fire(true) end)
step("disable-context", function() context.Enabled = false end)
step("disabled-context-fire", function() action:Fire(true) end)
step("enable-context", function() context.Enabled = true end)
step("true-in-context", function() action:Fire(true) end)
step("unparent", function() action.Parent = nil end)
step("reparent", function() action.Parent = context end)
step("number-type", function() action.Type = Enum.InputActionType.Direction1D end)
step("number", function() action:Fire(2) end)
step("number-duplicate", function() action:Fire(2) end)
step("number-disable", function() action.Enabled = false end)
step("number-enable", function() action.Enabled = true end)
step("number-negative", function() action:Fire(-2) end)
local clone = action:Clone()
table.insert(log, "clone:" .. tostring(clone:GetState()))
clone:Destroy()
step("vector-type", function() action.Type = Enum.InputActionType.Direction2D end)
step("vector", function() action:Fire(Vector2.new(2, -2)) end)
step("vector-duplicate", function() action:Fire(Vector2.new(2, -2)) end)
step("destroy", function() action:Destroy() end)
context:Destroy()
local expected = {
	"initial:false", "unparented:false", "parented:false", "false:false",
	"Pressed:nil:true", "StateChanged:true:true", "true:true", "duplicate:true",
	"Released:nil:false", "StateChanged:false:false", "disable-action:false", "disabled-fire:false",
	"enable-action:false", "Pressed:nil:true", "StateChanged:true:true", "true-again:true",
	"Released:nil:false", "StateChanged:false:false", "disable-context:false", "disabled-context-fire:false",
	"enable-context:false", "Pressed:nil:true", "StateChanged:true:true", "true-in-context:true",
	"Released:nil:false", "StateChanged:false:false", "unparent:false", "reparent:false",
	"StateChanged:0:0", "number-type:0", "StateChanged:2:2", "number:2", "number-duplicate:2",
	"StateChanged:0:0", "number-disable:0", "number-enable:0", "StateChanged:-2:-2", "number-negative:-2",
	"clone:0", "StateChanged:0, 0:0, 0", "vector-type:0, 0", "StateChanged:2, -2:2, -2",
	"vector:2, -2", "vector-duplicate:2, -2", "StateChanged:0, 0:0, 0", "destroy:0, 0",
}
assert(#log == #expected, "input action event count: " .. table.concat(log, " | "))
for index, entry in expected do
	assert(log[index] == entry, tostring(index) .. ": expected " .. entry .. "; got " .. log[index])
end
return true
]==]
