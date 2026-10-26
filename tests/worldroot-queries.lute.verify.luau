--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect
local Lute = require "../src/lute"
local D = require "../src/roblox/datatypes"
local E = require "../src/roblox/environment"

type Instance = E.Instance
type Vector = D.Vector3Value
type Frame = D.CFrameValue
type Hit = { Instance: Instance, Position: Vector, Normal: Vector, Distance: number, Material: unknown }
type Ray = (Instance, Vector, Vector, D.RaycastParamsValue?) -> Hit?
type Block = (Instance, Frame, Vector, Vector, D.RaycastParamsValue?) -> Hit?
type Sphere = (Instance, Vector, number, Vector, D.RaycastParamsValue?) -> Hit?
type Shape = (Instance, Instance, Vector, D.RaycastParamsValue?, Frame?, Vector?) -> Hit?
type Bounds = (Instance, Frame, Vector, D.OverlapParamsValue?) -> { Instance }
type Radius = (Instance, Vector, number, D.OverlapParamsValue?) -> { Instance }
type Parts = (Instance, Instance, D.OverlapParamsValue?) -> { Instance }
local V, CF = D.Vector3, D.CFrame

local function close(actual: number, expected: number)
	expect(math.abs(actual - expected) < 0.0001):toBe(true)
end

local function refused(callback: () -> (), message: string)
	local ok, failure = pcall(function(): unknown
		callback()
		return nil
	end)
	expect(ok):toBe(false)
	expect(string.find(tostring(failure), message, 1, true) ~= nil):toBe(true)
end

for _, method in { "Raycast", "Blockcast", "Spherecast", "Shapecast" } do
	describe(method, function()
		local function fixture()
			local engine = Lute.fixture.bridge().placeEngine()
			local world = engine.service "Workspace"
			local folder = engine.newInstance "Folder"
			folder.Parent = world
			local target = engine.newInstance "Part"
			target.Size, target.CFrame, target.Parent = V.new(10, 2, 10), CF.new(0, 0, 0), folder
			local source = engine.newInstance "Part"
			source.Size, source.CFrame, source.Parent = V.new(2, 2, 2), CF.new(0, 10, 0), world
			local function query(params: D.RaycastParamsValue?, direction: Vector?): Hit?
				local d = direction or V.new(0, -20, 0)
				if method == "Raycast" then
					return (world.Raycast :: Ray)(world, (source.CFrame :: Frame).Position, d, params)
				elseif method == "Blockcast" then
					return (world.Blockcast :: Block)(world, source.CFrame :: Frame, source.Size :: Vector, d, params)
				elseif method == "Spherecast" then
					return (world.Spherecast :: Sphere)(world, (source.CFrame :: Frame).Position, 1, d, params)
				end
				return (world.Shapecast :: Shape)(world, source, d, params)
			end
			local params = D.RaycastParams.new()
			params.ExcludeInstances = { source }
			return engine, world, target, source, folder, query, params
		end
		it("returns nearest rotated surface geometry and material without moving the source", function()
			local engine, world, target, source, _, query, params = fixture()
			target.CFrame = CF.Angles(0, 0, math.pi / 6)
			target.Material = engine.datatypes.Enum.Material.Wood
			local hit = assert(query(params))
			expect(hit.Instance):toBe(target)
			expect(engine.typeName(hit)):toBe "RaycastResult"
			expect(hit.Material):toBe(target.Material)
			expect((hit.Normal - V.new(-0.5, math.sqrt(3) / 2, 0)).Magnitude < 0.0001):toBe(true)
			local expected = if method == "Raycast"
				then 10 - 2 / math.sqrt(3)
				elseif method == "Spherecast" then 10 - 4 / math.sqrt(3)
				else 10 - (2 + 1 + math.sqrt(3)) / math.sqrt(3)
			close(hit.Distance, expected)
			close((target.CFrame :: Frame):PointToObjectSpace(hit.Position).Y, 1)
			expect(source.CFrame):toEqual(CF.new(0, 10, 0))
		end)
		it("honors descendant filters, empty inclusion, exclusions, and query flags", function()
			local engine, _, target, _, folder, query, params = fixture()
			params.FilterType = engine.datatypes.Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { folder }
			expect(assert(query(params)).Instance):toBe(target)
			params.IncludeInstances = {}
			expect(query(params)):toBe(nil)
			params.IncludeInstances = { folder }
			params.ExcludeInstances = { target }
			expect(query(params)):toBe(nil)
			params.ExcludeInstances = nil
			target.CanCollide, target.CanQuery, target.CanTouch = false, true, false
			expect(assert(query(params)).Instance):toBe(target)
			params.RespectCanCollide = true
			expect(query(params)):toBe(nil)
			params.RespectCanCollide = false
			target.CanQuery = false
			expect(query(params)):toBe(nil)
			target.CanCollide = true
			expect(assert(query(params)).Instance):toBe(target)
			params.BruteForceAllSlow = true
			target.CanCollide = false
			expect(assert(query(params)).Instance):toBe(target)
		end)
		it("misses short, zero and outward sweeps and skips initial intersections", function()
			local _, _, _, source, _, query, params = fixture()
			expect(query(params, V.zero)):toBe(nil)
			expect(query(params, V.new(0, -2, 0))):toBe(nil)
			expect(query(params, V.new(0, 20, 0))):toBe(nil)
			source.CFrame = CF.identity
			expect(query(params)):toBe(nil)
		end)
		it("refuses unsupported content, expansion and excessive distance", function()
			local _, _, target, _, _, query, params = fixture()
			target.Shape = D.Enum.PartType.Ball
			refused(function()
				query(params)
			end, "unsupported_content")
			target.Shape = D.Enum.PartType.Block
			params.Margin = 0.1
			refused(function()
				query(params)
			end, "unsupported")
			params.Margin, params.SizeGradient = 0, 0.5
			refused(function()
				query(params)
			end, "unsupported")
			params.SizeGradient = 0
			refused(function()
				query(params, V.new(0, -20000, 0))
			end, "maximum distance")
			refused(function()
				query(params, V.new(0, math.sqrt(-1), 0))
			end, "finite")
		end)
	end)
end

for _, method in { "GetPartBoundsInBox", "GetPartBoundsInRadius", "GetPartsInPart" } do
	describe(method, function()
		local function fixture()
			local engine = Lute.fixture.bridge().placeEngine()
			local world = engine.service "Workspace"
			local source = engine.newInstance "Part"
			source.Size, source.CFrame, source.Parent = V.new(4, 4, 4), CF.identity, world
			local folder = engine.newInstance "Folder"
			folder.Parent = world
			local target = engine.newInstance "Part"
			target.Size, target.CFrame, target.Parent =
				V.new(8, 1, 1), CF.new(4, 0, 0) * CF.Angles(0, 0, math.pi / 2), folder
			local function query(params: D.OverlapParamsValue?): { Instance }
				if method == "GetPartBoundsInBox" then
					return (world.GetPartBoundsInBox :: Bounds)(
						world,
						source.CFrame :: Frame,
						source.Size :: Vector,
						params
					)
				elseif method == "GetPartBoundsInRadius" then
					return (world.GetPartBoundsInRadius :: Radius)(world, (source.CFrame :: Frame).Position, 2, params)
				end
				return (world.GetPartsInPart :: Parts)(world, source, params)
			end
			local params = D.OverlapParams.new()
			params.ExcludeInstances = { source }
			return engine, world, source, target, folder, query, params
		end
		it("uses rotated target bounds rather than enclosing world axes and finds later movement", function()
			local _, _, _, target, _, query, params = fixture()
			expect(#query(params)):toBe(0)
			target.CFrame = CF.new(4, 0, 0)
			expect(query(params)):toEqual { target }
			target:Destroy()
			expect(#query(params)):toBe(0)
		end)
		it("honors descendant filters and CanQuery CanCollide CanTouch", function()
			local _, _, _, target, folder, query, params = fixture()
			target.CFrame = CF.identity
			params.FilterType, params.FilterDescendantsInstances = D.Enum.RaycastFilterType.Include, { folder }
			expect(query(params)):toEqual { target }
			params.IncludeInstances = {}
			expect(#query(params)):toBe(0)
			params.IncludeInstances = { folder }
			params.ExcludeInstances = { target }
			expect(#query(params)):toBe(0)
			params.ExcludeInstances = nil
			target.CanTouch, target.CanCollide, target.CanQuery = false, false, true
			expect(query(params)):toEqual { target }
			params.RespectCanCollide = true
			expect(#query(params)):toBe(0)
			params.RespectCanCollide = false
			target.CanQuery = false
			expect(#query(params)):toBe(0)
			target.CanCollide = true
			expect(query(params)):toEqual { target }
			target.CanCollide, params.BruteForceAllSlow = false, true
			expect(query(params)):toEqual { target }
		end)
		it("limits matching results, zero means unlimited, and excludes its source", function()
			local engine, _, _, target, folder, query, params = fixture()
			target.CFrame = CF.identity
			local second = engine.newInstance "Part"
			second.Size, second.CFrame, second.Parent = V.one, CF.identity, folder
			expect(#query(params)):toBe(2)
			params.MaxParts = 1
			expect(#query(params)):toBe(1)
			params.MaxParts = 0
			expect(#query(params)):toBe(2)
		end)
		it("refuses unsupported tolerance and invalid limits", function()
			local _, _, _, _, _, query, params = fixture()
			params.Tolerance = 0.01
			refused(function()
				query(params)
			end, "unsupported")
			params.Tolerance, params.MaxParts = 0, -1
			refused(function()
				query(params)
			end, "MaxParts")
		end)
	end)
end

for _, method in
	{
		"Raycast",
		"Blockcast",
		"Spherecast",
		"Shapecast",
		"GetPartBoundsInBox",
		"GetPartBoundsInRadius",
		"GetPartsInPart",
	}
do
	it(method .. " respects collision groups and isolates nested WorldModels", function()
		local engine = Lute.fixture.bridge().placeEngine()
		local world = engine.service "Workspace"
		local physics = engine.service "PhysicsService"
		local register = physics.RegisterCollisionGroup :: (Instance, string) -> ()
		local set = physics.CollisionGroupSetCollidable :: (Instance, string, string, boolean) -> ()
		register(physics, "Sensor")
		register(physics, "Hidden")
		set(physics, "Sensor", "Hidden", false)
		local target = engine.newInstance "Part"
		target.CFrame, target.Size, target.CollisionGroup, target.Parent = CF.identity, V.one * 2, "Hidden", world
		local source = engine.newInstance "Part"
		source.CFrame, source.Size, source.Parent = CF.new(0, 10, 0), V.one, world
		local model = engine.newInstance "WorldModel"
		model.Parent = world
		local nested = engine.newInstance "Part"
		nested.CFrame, nested.Size, nested.Parent = CF.new(0, 5, 0), V.one * 2, model
		local rayParams, overlapParams = D.RaycastParams.new(), D.OverlapParams.new()
		rayParams.CollisionGroup, overlapParams.CollisionGroup = "Sensor", "Sensor"
		rayParams.ExcludeInstances, overlapParams.ExcludeInstances = { source }, { source }
		local function query(): number
			local direction = V.new(0, -20, 0)
			if method == "Raycast" then
				return if (world.Raycast :: Ray)(world, V.new(0, 10, 0), direction, rayParams) then 1 else 0
			elseif method == "Blockcast" then
				return if (world.Blockcast :: Block)(world, CF.new(0, 10, 0), V.one, direction, rayParams) then 1 else 0
			elseif method == "Spherecast" then
				return if (world.Spherecast :: Sphere)(world, V.new(0, 10, 0), 1, direction, rayParams) then 1 else 0
			elseif method == "Shapecast" then
				return if (world.Shapecast :: Shape)(world, source, direction, rayParams) then 1 else 0
			elseif method == "GetPartBoundsInBox" then
				return #(world.GetPartBoundsInBox :: Bounds)(world, CF.identity, V.one, overlapParams)
			elseif method == "GetPartBoundsInRadius" then
				return #(world.GetPartBoundsInRadius :: Radius)(world, V.zero, 1, overlapParams)
			end
			source.CFrame = CF.identity
			return #(world.GetPartsInPart :: Parts)(world, source, overlapParams)
		end
		expect(query()):toBe(0)
		set(physics, "Hidden", "Sensor", true)
		expect(query()):toBe(1)
		set(physics, "Sensor", "Hidden", false)
		rayParams.BruteForceAllSlow, overlapParams.BruteForceAllSlow = true, true
		expect(query()):toBe(1)
		rayParams.BruteForceAllSlow, overlapParams.BruteForceAllSlow = false, false
		rayParams.CollisionGroup, overlapParams.CollisionGroup = "Unregistered", "Unregistered"
		expect(query()):toBe(1)
		local nestedRay = model.Raycast :: Ray
		expect(assert(nestedRay(model, V.new(0, 10, 0), V.new(0, -20, 0))).Instance):toBe(nested)
		local independent = Lute.fixture.bridge().placeEngine()
		local otherPhysics = independent.service "PhysicsService"
		expect((otherPhysics.IsCollisionGroupRegistered :: (Instance, string) -> boolean)(otherPhysics, "Hidden")):toBe(
			false
		)
	end)
end

it("ball volume differs from bounds and casts resolve sphere corners rather than an expanded box", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local target = engine.newInstance "Part"
	target.Size, target.Shape, target.Parent = V.one * 2, D.Enum.PartType.Ball, world
	local origin, direction = V.new(0.9, 5, 0.9), V.new(0, -10, 0)
	expect((world.Raycast :: Ray)(world, origin, direction)):toBe(nil)
	local hit = assert((world.Raycast :: Ray)(world, V.new(0, 5, 0), direction))
	close(hit.Distance, 4)
	expect(hit.Normal):toEqual(V.yAxis)
	local sphereHit = assert((world.Spherecast :: Sphere)(world, V.new(0, 5, 0), 1, direction))
	close(sphereHit.Distance, 3)
	local blockHit = assert((world.Blockcast :: Block)(world, CF.new(0, 5, 0), V.one * 2, direction))
	close(blockHit.Distance, 3)
	target.Shape = D.Enum.PartType.Block
	local corner = assert((world.Spherecast :: Sphere)(world, V.new(1.6, 5, 1.6), 1, direction))
	close(corner.Distance, 4 - math.sqrt(0.28))
	expect((corner.Position - V.new(1, 1, 1)).Magnitude < 0.0001):toBe(true)
	expect((world.Spherecast :: Sphere)(world, V.new(1.8, 5, 1.8), 1, direction)):toBe(nil)
	local source = engine.newInstance "Part"
	source.Size, source.Shape, source.CFrame, source.Parent = V.one * 2, D.Enum.PartType.Ball, CF.new(0, 5, 0), world
	close(assert((world.Shapecast :: Shape)(world, source, direction)).Distance, 3)
	source.CFrame, source.Size = CF.new(1.8, 1.8, 1.8), V.one * 0.2
	target.Shape = D.Enum.PartType.Ball
	expect(#(world.GetPartsInPart :: Parts)(world, source)):toBe(0)
	local params = D.OverlapParams.new()
	params.ExcludeInstances = { source }
	expect(#(world.GetPartBoundsInBox :: Bounds)(world, CF.new(0.95, 0.95, 0.95), V.one * 0.1, params)):toBe(1)
	expect(#(world.GetPartBoundsInRadius :: Radius)(world, V.new(0.95, 0.95, 0.95), 0.1, params)):toBe(1)
end)

it("rotates the query box and source shape, including oblique box edge contacts", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local target = engine.newInstance "Part"
	target.Size, target.CFrame, target.Parent = V.one * 0.2, CF.new(3, 0, 0), world
	local size = V.new(8, 1, 1)
	expect(#(world.GetPartBoundsInBox :: Bounds)(world, CF.identity, size)):toBe(1)
	expect(#(world.GetPartBoundsInBox :: Bounds)(world, CF.Angles(0, 0, math.pi / 2), size)):toBe(0)
	local source = engine.newInstance "Part"
	source.CFrame, source.Size, source.Parent = CF.Angles(0, 0, math.pi / 2), size, world
	expect(#(world.GetPartsInPart :: Parts)(world, source)):toBe(0)
	source.CFrame = CF.identity
	expect(#(world.GetPartsInPart :: Parts)(world, source)):toBe(1)
	source.CFrame = CF.new(0, 10, 0) * CF.Angles(0, 0, math.pi / 2)
	local params = D.RaycastParams.new()
	params.ExcludeInstances = { source }
	expect((world.Blockcast :: Block)(world, source.CFrame :: Frame, size, V.new(0, -20, 0), params)):toBe(nil)
	expect((world.Shapecast :: Shape)(world, source, V.new(0, -20, 0), params)):toBe(nil)
	source.CFrame = CF.new(0, 10, 0)
	expect(assert((world.Shapecast :: Shape)(world, source, V.new(0, -20, 0), params)).Instance):toBe(target)
	target.Size, target.CFrame = V.new(5, 1, 2), CF.Angles(0.2, 0.5, 0.3)
	local result = assert(
		(world.Blockcast :: Block)(
			world,
			CF.new(0, 10, 0) * CF.Angles(0.1, 0.7, 0.4),
			V.new(2, 1, 3),
			V.new(0, -20, 0),
			params
		)
	)
	close(result.Normal.Magnitude, 1)
	expect(result.Distance > 0 and result.Distance < 10):toBe(true)
end)

it("cylinder mesh union and terrain proxies use authored bounds and water filtering applies only to terrain", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local origin, direction = V.new(0, 10, 0), V.new(0, -20, 0)
	for _, class in { "Part", "MeshPart", "UnionOperation", "Terrain" } do
		local target = engine.environment.createEngineInstance(class)
		engine.environment.poke(target, "CFrame", CF.identity)
		engine.environment.poke(target, "Size", V.one * 2)
		engine.environment.poke(target, "Material", D.Enum.Material.Water)
		if class == "Part" then
			target.Shape = D.Enum.PartType.Cylinder
		end
		target.Parent = world
		local params = D.RaycastParams.new()
		expect(assert((world.Raycast :: Ray)(world, origin, direction, params), class).Instance):toBe(target)
		params.IgnoreWater = true
		local hit = (world.Raycast :: Ray)(world, origin, direction, params)
		expect(if hit then hit.Instance else nil):toBe(if class == "Terrain" then nil else target)
		expect(#(world.GetPartBoundsInRadius :: Radius)(world, V.zero, 1)):toBe(1)
		target:Destroy()
	end
end)

it("refuses invalid cast geometry and unsupported source content before returning a miss", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local direction = V.new(0, -20, 0)
	refused(function()
		(world.Blockcast :: Block)(world, CF.identity, V.one * 513, direction)
	end, "maximum size")
	refused(function()
		(world.Blockcast :: Block)(world, CF.identity, V.new(-1, 1, 1), direction)
	end, "positive")
	refused(function()
		(world.Spherecast :: Sphere)(world, V.zero, 257, direction)
	end, "maximum size")
	refused(function()
		(world.Spherecast :: Sphere)(world, V.zero, -1, direction)
	end, "positive")
	refused(function()
		(world.GetPartBoundsInRadius :: Radius)(world, V.zero, -1)
	end, "nonnegative")
	local source = engine.newInstance "WedgePart"
	source.Parent = world
	refused(function()
		(world.Shapecast :: Shape)(world, source, direction)
	end, "unsupported_content")
	refused(function()
		(world.GetPartsInPart :: Parts)(world, source)
	end, "unsupported_content")
	source:Destroy()
	refused(function()
		(world.Shapecast :: Shape)(world, source, direction)
	end, "live BasePart")
	local part = engine.newInstance "Part"
	refused(function()
		(world.GetPartsInPart :: Parts)(world, part)
	end, "same WorldRoot")
	refused(function()
		(world.Shapecast :: Shape)(world, part, direction, nil, CF.identity)
	end, "unsupported")
end)

it("unconfigured terrain refuses even after an overlap limit could have been satisfied", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local part = engine.newInstance "Part"
	part.Size, part.Parent = V.one * 2, world
	local terrain = engine.environment.createEngineInstance "Terrain"
	terrain.Parent = world
	refused(function()
		(world.Raycast :: Ray)(world, V.new(0, 10, 0), V.new(0, -20, 0))
	end, "unsupported_content")
	local params = D.OverlapParams.new()
	params.MaxParts = 1
	refused(function()
		(world.GetPartBoundsInBox :: Bounds)(world, CF.identity, V.one, params)
	end, "unsupported_content")
	params.ExcludeInstances = { terrain }
	expect(#(world.GetPartBoundsInBox :: Bounds)(world, CF.identity, V.one, params)):toBe(1)
end)

it("ball intersections include tangency and exclude inside ray origins", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local world = engine.service "Workspace"
	local target = engine.newInstance "Part"
	target.Shape, target.Size, target.Parent = D.Enum.PartType.Ball, V.one * 2, world
	local tangent = assert((world.Raycast :: Ray)(world, V.new(1, 5, 0), V.new(0, -10, 0)))
	close(tangent.Distance, 5)
	expect(tangent.Normal):toEqual(V.xAxis)
	expect((world.Raycast :: Ray)(world, V.zero, V.new(0, -10, 0))):toBe(nil)
	local source = engine.newInstance "Part"
	source.Shape, source.Size, source.Parent = D.Enum.PartType.Ball, V.one * 2, world
	source.CFrame = CF.new(2, 0, 0)
	expect((world.GetPartsInPart :: Parts)(world, source)):toEqual { target }
	source.CFrame = CF.new(2.01, 0, 0)
	expect(#(world.GetPartsInPart :: Parts)(world, source)):toBe(0)
	local hit = assert((world.Shapecast :: Shape)(world, source, V.new(-4, 0, 0)))
	close(hit.Distance, 0.01)
	expect(hit.Normal):toEqual(V.xAxis)
end)

return nil
