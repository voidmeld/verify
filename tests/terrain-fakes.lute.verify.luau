--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local D = require "../src/roblox/datatypes"
local Queries = require "../src/roblox/spatial-query-fakes"
local expect, it = Test.expect, Test.it

local function fixture()
	local engine = Lute.fixture.bridge().placeEngine()
	local env, types = engine.environment, engine.datatypes
	local world = engine.service "Workspace"
	local terrain = engine.newInstance("Terrain", true)
	terrain.Parent = world
	local params = types.RaycastParams.new()
	params.FilterType = types.Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	local function ray(origin: D.Vector3Value, direction: D.Vector3Value)
		local result = env.method(world, "Raycast")(world, origin, direction, params)
		return if result then Queries.expectResult(result) else nil
	end
	return engine, terrain, params, ray
end

it("terrain edits carve and replace bounded materials without changing later fills", function()
	local engine, terrain, params, ray = fixture()
	local env, types = engine.environment, engine.datatypes
	local V, C, M = types.Vector3, types.CFrame, types.Enum.Material
	local fill, replace = env.method(terrain, "FillBlock"), env.method(terrain, "ReplaceMaterial")
	local region = types.Region3.new(V.new(-4, -4, -4), V.new(4, 4, 4))
	fill(terrain, C.new(0, -2, 0), V.new(24, 4, 16), M.Grass)
	local function down(x: number, z: number)
		return ray(V.new(x, 12, z), V.new(0, -32, 0))
	end
	local before = assert(down(0, 0))
	replace(terrain, region, 4, M.Grass, M.Ground)
	local after = assert(down(0, 0))
	expect(after.Material):toBe(M.Ground)
	expect(after.Position):toBe(before.Position)
	expect(after.Normal):toBe(V.yAxis)
	expect(after.Instance):toBe(terrain)
	expect(after.Distance):toBe(12)
	expect(assert(down(4, 0)).Material):toBe(M.Grass)
	fill(terrain, C.new(0, -2, 0), V.new(2, 4, 2), M.Air)
	expect(down(0, 0)):toBe(nil)
	replace(terrain, region, 4, M.Air, M.Rock)
	expect(down(0, 0)):toBe(nil)
	fill(terrain, C.new(0, 2, 0), V.new(2, 4, 2), M.Water)
	expect(assert(down(0, 0)).Material):toBe(M.Water)
	params.IgnoreWater = true
	expect(down(0, 0)):toBe(nil)
	fill(terrain, C.new(0, -6, 0), V.new(2, 4, 2), M.Rock)
	expect(assert(down(0, 0)).Position.Y):toBe(-4)
	params.FilterDescendantsInstances = {}
	expect(down(0, 0)):toBe(nil)
	params.FilterDescendantsInstances = { terrain }
	env.method(terrain, "Clear")(terrain)
	expect(down(0, 0)):toBe(nil)
end)

it("terrain primitives support rotated and horizontal rays and nearest parts", function()
	local engine, terrain, params, ray = fixture()
	local env, types = engine.environment, engine.datatypes
	local V, C, M = types.Vector3, types.CFrame, types.Enum.Material
	env.method(terrain, "FillBall")(terrain, V.zero, 4, M.Rock)
	local hit = assert(ray(V.new(-10, 0, 0), V.new(20, 0, 0)))
	expect(hit.Position):toBe(V.new(-4, 0, 0))
	expect(hit.Normal):toBe(-V.xAxis)
	expect(ray(V.new(-10, 5, 0), V.new(20, 0, 0))):toBe(nil)
	env.method(terrain, "Clear")(terrain)
	env.method(terrain, "FillCylinder")(terrain, C.identity, 8, 3, M.Grass)
	expect(assert(ray(V.new(0, 10, 0), V.new(0, -20, 0))).Position.Y):toBe(4)
	expect(assert(ray(V.new(-10, 0, 0), V.new(20, 0, 0))).Position.X):toBe(-3)
	env.method(terrain, "Clear")(terrain)
	env.method(terrain, "FillBlock")(terrain, C.Angles(0, 0, math.pi / 4), V.new(8, 2, 8), M.Ground)
	local rotated = assert(ray(V.new(0, 10, 0), V.new(0, -20, 0)))
	expect(math.abs(rotated.Position.Y - math.sqrt(2)) < 0.00001):toBe(true)
	local roof = engine.newInstance "Part"
	roof.Size, roof.Position, roof.Parent = V.new(8, 1, 8), V.new(0, 5, 0), engine.service "Workspace"
	params.FilterDescendantsInstances = { terrain, roof }
	expect(assert(ray(V.new(0, 10, 0), V.new(0, -20, 0))).Instance):toBe(roof)
	params.FilterDescendantsInstances = { terrain }
	expect(
		pcall(
			env.method(engine.service "Workspace", "Spherecast"),
			engine.service "Workspace",
			V.new(0, 10, 0),
			1,
			V.new(0, -20, 0),
			params
		)
	):toBe(false)
	expect(pcall(env.method(terrain, "FillBall"), terrain, V.zero, -1, M.Rock)):toBe(false)
end)

it("voxel writes copy all layers and validate atomically before replacing terrain", function()
	local engine, terrain, _, ray = fixture()
	local env, types = engine.environment, engine.datatypes
	local V, M = types.Vector3, types.Enum.Material
	local region = types.Region3.new(V.zero, V.new(4, 8, 4))
	local write, replace = env.method(terrain, "WriteVoxels"), env.method(terrain, "ReplaceMaterial")
	local materials, occupancy = { { { M.Grass }, { M.Water } } }, { { { 0.5 }, { 1 } } }
	write(terrain, region, 4, materials, occupancy)
	materials[1][2][1], occupancy[1][2][1] = M.Rock, 0
	local function down()
		return ray(V.new(2, 12, 2), V.new(0, -20, 0))
	end
	expect(assert(down()).Position.Y):toBe(8)
	expect(assert(down()).Material):toBe(M.Water)
	expect(pcall(write, terrain, region, 2, materials, occupancy)):toBe(false)
	expect(pcall(write, terrain, region, 4, materials, { { { 0.5 }, { 2 } } })):toBe(false)
	expect(pcall(write, terrain, region, 4, {}, {})):toBe(false)
	expect(assert(down()).Material):toBe(M.Water)
	replace(terrain, region, 4, M.Water, M.Air)
	expect(assert(down()).Position.Y):toBe(2)
	expect(assert(down()).Material):toBe(M.Grass)
	local unaligned = types.Region3.new(V.new(1, 0, 0), V.new(5, 4, 4))
	expect(pcall(replace, terrain, unaligned, 4, M.Grass, M.Rock)):toBe(false)
	write(terrain, region, 4, { { { M.Air }, { M.Air } } }, { { { 0 }, { 0 } } })
	expect(down()):toBe(nil)
end)

return nil
