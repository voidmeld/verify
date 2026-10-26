--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Datatypes = require "../src/roblox/datatypes"

it("block raycasts preserve rotated hit geometry and reject inside origins", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local types = engine.datatypes
	local world = engine.service "Workspace"
	local ray = world.Raycast :: (
		typeof(world),
		Datatypes.Vector3Value,
		Datatypes.Vector3Value,
		Datatypes.RaycastParamsValue?
	) -> {
		Instance: typeof(world),
		Position: Datatypes.Vector3Value,
		Normal: Datatypes.Vector3Value,
		Distance: number,
	}?
	local part = engine.newInstance "Part"
	part.Size = types.Vector3.new(10, 2, 10)
	part.CFrame = types.CFrame.new(0, 100, 0) * types.CFrame.Angles(0, 0, math.rad(30))
	part.Parent = world
	local origin, down = types.Vector3.new(0, 110, 0), types.Vector3.new(0, -20, 0)
	local hit = assert(ray(world, origin, down))
	expect(engine.typeName(hit)):toBe "RaycastResult"
	expect(hit.Instance):toBe(part)
	expect(math.abs(hit.Distance - 8.845298767089844) < 0.00001):toBe(true)
	expect((hit.Normal - types.Vector3.new(-0.5, math.sqrt(3) / 2, 0)).Magnitude < 0.00001):toBe(true)
	expect((hit.Position - types.Vector3.new(0, 101.15470123291016, 0)).Magnitude < 0.00001):toBe(true)
	expect(ray(world, types.Vector3.new(0, 100, 0), down)):toBe(nil)
	expect(ray(world, origin, types.Vector3.zero)):toBe(nil)
	expect(ray(world, origin, types.Vector3.new(0, -4, 0))):toBe(nil)
end)
it("ray filters select the closest eligible block and refuse unknown collision geometry", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local types = engine.datatypes
	local world = engine.service "Workspace"
	local ray = world.Raycast :: (
		typeof(world),
		Datatypes.Vector3Value,
		Datatypes.Vector3Value,
		Datatypes.RaycastParamsValue?
	) -> { Instance: typeof(world) }?
	local group = engine.newInstance "Folder"
	group.Parent = world
	local near = engine.newInstance "Part"
	near.Position, near.Size, near.Parent = types.Vector3.new(0, 5, 0), types.Vector3.new(4, 2, 4), group
	local far = engine.newInstance "Part"
	far.Position, far.Size, far.Parent = types.Vector3.zero, types.Vector3.new(4, 2, 4), world
	local origin, down = types.Vector3.new(0, 10, 0), types.Vector3.new(0, -20, 0)
	local params = types.RaycastParams.new()
	expect(assert(ray(world, origin, down, params)).Instance):toBe(near)
	params.FilterDescendantsInstances = { group }
	expect(assert(ray(world, origin, down, params)).Instance):toBe(far)
	params.FilterType = types.Enum.RaycastFilterType.Include
	expect(assert(ray(world, origin, down, params)).Instance):toBe(near)
	params.ExcludeInstances = { near }
	expect(ray(world, origin, down, params)):toBe(nil)
	params.ExcludeInstances = nil
	near.CanCollide, near.CanQuery = false, false
	expect(ray(world, origin, down, params)):toBe(nil)
	near.CanQuery = true
	expect(assert(ray(world, origin, down, params)).Instance):toBe(near)
	params.RespectCanCollide = true
	expect(ray(world, origin, down, params)):toBe(nil)
	params.RespectCanCollide = false
	near.Shape = types.Enum.PartType.Ball
	expect((pcall(ray, world, origin, down, params))):toBe(false)
end)

return nil
