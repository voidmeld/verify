--!strict

local function asNumber(value: unknown): number
	assert(type(value) == "number")
	return value
end

local Core = require "../src/core"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local function scale(model: Roblox.Instance, value: number)
	(model.ScaleTo :: (Roblox.Instance, number) -> ())(model, value)
end

local function factor(model: Roblox.Instance): number
	return (model.GetScale :: (Roblox.Instance) -> number)(model)
end

return function(suite: Core.Harness)
	suite:case("model scaling preserves pivot, nested factors, edits and clone scale", function(check)
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
		check:expect(factor(model)):toBe(2)
		check:expect(factor(nested)):toBe(6)
		check:expect(part.Size):toBe(types.Vector3.new(4, 8, 12))
		check:expect(part.Position):toBe(types.Vector3.new(9, 0, 0))
		check:expect(child.Position):toBe(types.Vector3.new(29, 0, 0))
		check:expect(child.Size):toBe(types.Vector3.new(12, 12, 12))
		check:expect(factor(assert(model:Clone()))):toBe(2)
		part.Size = types.Vector3.new(10, 10, 10)
		scale(model, 4)
		check:expect(part.Size):toBe(types.Vector3.new(20, 20, 20))
		scale(model, 1)
		check:expect(part.Size):toBe(types.Vector3.new(5, 5, 5))
		check:expect(factor(nested)):toBe(3)
		scale(nested, 1)
		check:expect(child.Size):toBe(types.Vector3.new(2, 2, 2))
	end)
	suite:case("model scaling distinguishes constraint geometry from motor transforms and light range", function(check)
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
		check:expect(attachment.CFrame):toBe(types.CFrame.new(2, 4, 6))
		check:expect(motor.C0):toBe(types.CFrame.new(2, 4, 6))
		check:expect(motor.Transform):toBe(types.CFrame.new(3, 4, 5))
		check:expect(light.Range):toBe(7)
		check:expect(animation.Transform):toBe(types.CFrame.new(2, 4, 6))
		check:expect(animation.MaxForce):toBe(48)
		check:expect(animation.MaxTorque):toBe(56)
		check:expect(animation.LinearStrength):toBe(5)
		check:expect(animation.AngularDamping):toBe(2)
		check:expect(mesh.Scale):toBe(types.Vector3.new(4, 6, 8))
		check:expect(humanoid.WalkSpeed):toBe(32)
		check:expect(math.abs((asNumber(humanoid.JumpPower)) - 70.71067810058594) < 0.00001):toBe(true)
		check:expect(emitter.Size):toBe(types.NumberSequence.new(4))
		check:expect(emitter.Speed):toBe(types.NumberRange.new(4, 8))
		local constraint = engine.newInstance "HingeConstraint"
		constraint.Parent = model
		check
			:expect((pcall(function()
				scale(model, 4)
			end)))
			:toBe(false)
		check:expect(factor(model)):toBe(2)
		check:expect(attachment.CFrame):toBe(types.CFrame.new(2, 4, 6))
	end)
end
