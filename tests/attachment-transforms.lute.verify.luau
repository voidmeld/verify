--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Frames = require "../src/roblox/datatypes/cframe"
local Vectors = require "../src/roblox/datatypes/vector"

local function fixture(own: (() -> ()) -> ())
	local bridge = Lute.fixture.bridge()
	own(function()
		bridge.close()
	end)
	return bridge.placeEngine()
end

Test.it("attachment world transforms follow translated and rotated ancestral parts", function(own)
	local engine = fixture(own)
	local frame, vector = engine.datatypes.CFrame, engine.datatypes.Vector3
	local part = engine.newInstance "Part"
	part.CFrame = frame.new(10, 20, 30) * frame.Angles(0, math.pi / 2, 0)
	part.PivotOffset = frame.new(0, 50, 0)
	local folder = engine.newInstance "Folder"
	folder.Parent = part
	local attachment = engine.newInstance "Attachment"
	attachment.Parent, attachment.Position = folder, vector.new(2, 3, 4)
	Test.expect(attachment.CFrame):toBe(frame.new(2, 3, 4))
	local expected = Frames.expect(part.CFrame, 1) * frame.new(2, 3, 4)
	Test.expect(attachment.WorldCFrame):toBe(expected)
	Test.expect(attachment.WorldPosition):toBe(expected.Position)
	part.CFrame = frame.new(40, 50, 60)
	Test.expect(attachment.WorldPosition):toBe(vector.new(42, 53, 64))
end)

Test.it("nested and detached attachments use their nearest spatial ancestor", function(own)
	local engine = fixture(own)
	local frame, vector = engine.datatypes.CFrame, engine.datatypes.Vector3
	local model = engine.newInstance "Model"
	model.WorldPivot = frame.new(10, 20, 30)
	local outer, inner = engine.newInstance "Attachment", engine.newInstance "Attachment"
	outer.CFrame, outer.Parent = frame.new(1, 2, 3) * frame.Angles(0, 0, math.pi / 2), model
	inner.Position, inner.Parent = vector.new(4, 0, 0), outer
	local expected = frame.new(10, 20, 30) * Frames.expect(outer.CFrame, 1) * frame.new(4, 0, 0)
	Test.expect(inner.WorldCFrame):toBe(expected)
	outer.Parent = nil
	Test.expect(outer.WorldCFrame):toBe(outer.CFrame)
	Test.expect(inner.WorldCFrame):toBe(Frames.expect(outer.CFrame, 1) * frame.new(4, 0, 0))
end)

Test.it("world-space writes convert to local coordinates and retain rotation when moving", function(own)
	local engine = fixture(own)
	local frame, vector = engine.datatypes.CFrame, engine.datatypes.Vector3
	local part, attachment = engine.newInstance "Part", engine.newInstance "Attachment"
	part.CFrame = frame.new(10, 20, 30) * frame.Angles(0, math.pi / 2, 0)
	attachment.Parent = part
	local target = frame.new(50, 60, 70) * frame.Angles(0.1, 0.2, 0.3)
	attachment.WorldCFrame = target
	local localFrame = Frames.expect(attachment.CFrame, 1)
	local expected = Frames.expect(part.CFrame, 1):Inverse() * target
	Test.expect(localFrame:FuzzyEq(expected, 1e-6)):toBe(true)
	Test.expect(attachment.Position):toBe(localFrame.Position)
	attachment.WorldPosition = vector.new(80, 90, 100)
	Test.expect(Vectors.expect3(attachment.WorldPosition, 1):FuzzyEq(vector.new(80, 90, 100), 1e-6)):toBe(true)
	Test.expect(Frames.expect(attachment.CFrame, 1).Rotation:FuzzyEq(localFrame.Rotation, 1e-6)):toBe(true)
end)

Test.it("prompt range uses the attachment world position instead of the origin", function(own)
	local engine = fixture(own)
	local env, vector = engine.environment, engine.datatypes.Vector3
	local player = engine.newInstance("Player", true)
	local character = engine.newInstance "Model"
	local root = engine.newInstance "Part"
	root.Name, root.Parent, player.Character = "HumanoidRootPart", character, character
	local part = engine.newInstance "Part"
	part.Position, part.Parent = vector.new(0, 200, 0), engine.service "Workspace"
	local attachment = engine.newInstance "Attachment"
	attachment.Position, attachment.Parent = vector.new(0, 5, 0), part
	local prompt = engine.newInstance "ProximityPrompt"
	prompt.Enabled, prompt.MaxActivationDistance, prompt.Parent = true, 10, attachment
	local shown = 0
	env.event(prompt, "PromptShown"):Connect(function()
		shown += 1
	end)
	local host = Roblox.promptHost.simulated(engine, {
		player = player,
		visible = function()
			return true
		end,
	})
	own(function()
		host:Disconnect()
	end)
	env.fire(engine.service "RunService", "Heartbeat", 0)
	Test.expect(shown):toBe(0)
	root.Position = vector.new(0, 205, 0)
	env.fire(engine.service "RunService", "Heartbeat", 0)
	Test.expect(shown):toBe(1)
end)

return nil
