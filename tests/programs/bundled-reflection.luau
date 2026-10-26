--!strict

local Lute = require "../../src/lute"
local Roblox = require "../../src/roblox"

local snapshot = Lute.fixture.load()
assert(snapshot.engineVersion == "0.744.0.7441077")
local types = Roblox.reflectionSnapshot.library(snapshot)
local bridge = Lute.fixture.bridge()
local frame = bridge.environment.createInstance "Frame"
assert(frame.Name == "Frame")
assert(not pcall(function()
	frame.AbsoluteSize = types.Vector2.new(1, 2)
end))
for _, name in { "Player", "GuiService", "TextService", "UserInputService" } do
	assert(not pcall(function()
		bridge.engine.new(name)
	end))
end
local value = bridge.environment.createInstance "StringValue"
assert(value.Name == "Value")
print "bundled-reflection-ready"
