--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asNumber(value: unknown): number
	assert(type(value) == "number")
	return value
end

local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local function scale(model: Roblox.Instance, value: number)
	(model.ScaleTo :: (Roblox.Instance, number) -> ())(model, value)
end

local function factor(model: Roblox.Instance): number
	return (model.GetScale :: (Roblox.Instance) -> number)(model)
end

it("model scaling preserves pivot, nested factors, edits and clone scale", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local types = engine.datatypes
	local model = engine.newInstance "Model"
	local part = engine.newInstance "Part"
	part.Size, part.CFrame = types.Vector3.new(2, 4, 6), types.CFrame.new(10, 0, 0)
	part.PivotOffset, part.Parent = types.CFrame.new(1, 0, 0), model
	model.PrimaryPart = part
	local nested = engine.newInstance "Model"
	local child = engine.newInstance "Part"
	child.Size, child.CFrame, child.Parent = types.Vector3.new(2, 2, 2), types.CFrame.new(20, 0, 0), nested
	nested.PrimaryPart = child
	scale(nested, 3)
	nested.Parent = model
	scale(model, 2)
	expect(factor(model)):toBe(2)
	expect(factor(nested)):toBe(6)
	expect(part.Size):toBe(types.Vector3.new(4, 8, 12))
	expect(part.Position):toBe(types.Vector3.new(9, 0, 0))
	expect(child.Position):toBe(types.Vector3.new(29, 0, 0))
	expect(child.Size):toBe(types.Vector3.new(12, 12, 12))
	expect(factor(assert(model:Clone()))):toBe(2)
	part.Size = types.Vector3.new(10, 10, 10)
	scale(model, 4)
	expect(part.Size):toBe(types.Vector3.new(20, 20, 20))
	scale(model, 1)
	expect(part.Size):toBe(types.Vector3.new(5, 5, 5))
	expect(factor(nested)):toBe(3)
	scale(nested, 1)
	expect(child.Size):toBe(types.Vector3.new(2, 2, 2))
end)
it("model scaling distinguishes constraint geometry from motor transforms and light range", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local types = engine.datatypes
	local model = engine.newInstance "Model"
	local attachment = engine.newInstance "Attachment"
	attachment.CFrame, attachment.Parent = types.CFrame.new(1, 2, 3), model
	local motor = engine.newInstance "Motor6D"
	motor.C0, motor.Transform, motor.Parent = types.CFrame.new(1, 2, 3), types.CFrame.new(3, 4, 5), model
	local light = engine.newInstance "PointLight"
	light.Range, light.Parent = 7, model
	local animation = engine.newInstance "AnimationConstraint"
	animation.Transform, animation.Parent = types.CFrame.new(1, 2, 3), model
	animation.MaxForce, animation.MaxTorque = 6, 7
	animation.LinearStrength, animation.AngularDamping = 5, 2
	local mesh = engine.newInstance "SpecialMesh"
	mesh.MeshType, mesh.Scale, mesh.Parent = types.Enum.MeshType.FileMesh, types.Vector3.new(2, 3, 4), model
	local humanoid = engine.newInstance "Humanoid"
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.Parent = 16, 50, model
	local emitter = engine.newInstance "ParticleEmitter"
	emitter.Size, emitter.Speed, emitter.Parent = types.NumberSequence.new(2), types.NumberRange.new(2, 4), model
	scale(model, 2)
	expect(attachment.CFrame):toBe(types.CFrame.new(2, 4, 6))
	expect(motor.C0):toBe(types.CFrame.new(2, 4, 6))
	expect(motor.Transform):toBe(types.CFrame.new(3, 4, 5))
	expect(light.Range):toBe(7)
	expect(animation.Transform):toBe(types.CFrame.new(2, 4, 6))
	expect(animation.MaxForce):toBe(48)
	expect(animation.MaxTorque):toBe(56)
	expect(animation.LinearStrength):toBe(5)
	expect(animation.AngularDamping):toBe(2)
	expect(mesh.Scale):toBe(types.Vector3.new(4, 6, 8))
	expect(humanoid.WalkSpeed):toBe(32)
	expect(math.abs((asNumber(humanoid.JumpPower)) - 70.71067810058594) < 0.00001):toBe(true)
	expect(emitter.Size):toBe(types.NumberSequence.new(4))
	expect(emitter.Speed):toBe(types.NumberRange.new(4, 8))
	local constraint = engine.newInstance "HingeConstraint"
	constraint.Parent = model
	expect((pcall(function()
		scale(model, 4)
	end))):toBe(false)
	expect(factor(model)):toBe(2)
	expect(attachment.CFrame):toBe(types.CFrame.new(2, 4, 6))
end)

return nil
