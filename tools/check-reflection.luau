--!strict
local load = require :: (string) -> unknown
local roblox = load "@lune/roblox" :: {
	getReflectionDatabase: () -> unknown,
	Enum: { Material: { Plastic: unknown }, KeyCode: { A: unknown } },
	Vector3: { new: (number, number, number) -> unknown },
}
local Reflection = require "../src/roblox/reflection"
local env = Reflection.create {
	database = roblox.getReflectionDatabase() :: Reflection.Database,
	typeName = typeof,
	enumType = function(value)
		return tostring((value :: { EnumType: unknown }).EnumType)
	end,
}
local part = env.createInstance "Part"
assert(part.Size ~= nil)
assert(part.Anchored == false)
part.Anchored = true
part.Size = roblox.Vector3.new(2, 3, 4)
part.Material = roblox.Enum.Material.Plastic
assert(not pcall(function()
	part.Material = roblox.Enum.KeyCode.A
end))
assert(not pcall(function()
	part.Size = "invalid"
end))
assert(not pcall(function()
	part.UnknownProperty = true
end))
local label = env.createInstance "TextLabel"
assert(not pcall(function()
	label.AbsoluteSize = roblox.Vector3.new(1, 2, 3)
end))
assert(not pcall(function()
	part.Anchored = 42
end))
local model = env.createInstance "Model"
part.Parent = model
model.PrimaryPart = part
local clone = model:Clone()
assert(clone and clone.PrimaryPart == clone:GetChildren()[1])
print "reflection defaults, types and remapping passed"
