--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local E = require "../src/roblox/environment-types"
local D = require "../src/roblox/datatypes"
local Frames = require "../src/roblox/datatypes/cframe"
local Geometry = require "../src/roblox/query-geometry"
local Queries = require "../src/roblox/spatial-query-fakes"
local Index = require "../src/roblox/spatial-query-index"

local V, CF = D.Vector3, D.CFrame
type QueryName =
	"Raycast"
	| "Blockcast"
	| "Spherecast"
	| "Shapecast"
	| "GetPartBoundsInBox"
	| "GetPartBoundsInRadius"
	| "GetPartsInPart"
local methods: { QueryName } = {
	"Raycast",
	"Blockcast",
	"Spherecast",
	"Shapecast",
	"GetPartBoundsInBox",
	"GetPartBoundsInRadius",
	"GetPartsInPart",
}

local function fixture()
	local engine = Lute.fixture.bridge().placeEngine()
	local env, world = engine.environment, engine.service "Workspace"
	local scanning = false
	local counts = { scan = 0, indexed = 0 }
	Queries.attach(env, function(select: Index.Select): Index.Select
		return function(owner: E.Instance, source: Geometry.Shape, direction: D.Vector3Value): { E.Instance }
			if scanning then
				local parts = owner:GetDescendants()
				counts.scan += #parts
				return parts
			end
			local parts = select(owner, source, direction)
			counts.indexed += #parts
			return parts
		end
	end)
	local scan: { [string]: E.InstanceMethod } = {}
	local indexed: { [string]: E.InstanceMethod } = {}
	for _, method in methods do
		local callback = env.method(world, method)
		scan[method] = function(self: E.Object, ...: unknown): ...unknown
			scanning = true
			return callback(self, ...)
		end
		indexed[method] = function(self: E.Object, ...: unknown): ...unknown
			scanning = false
			return callback(self, ...)
		end
	end
	local physics = engine.service "PhysicsService"
	local register, collide =
		env.method(physics, "RegisterCollisionGroup"), env.method(physics, "CollisionGroupSetCollidable")
	register(physics, "Sensor")
	register(physics, "Hidden")
	collide(physics, "Sensor", "Hidden", false)
	return engine, world, scan, indexed, counts
end

local function compare(method: string, actual: unknown, expected: unknown)
	if method == "Raycast" or method == "Blockcast" or method == "Spherecast" or method == "Shapecast" then
		if expected == nil then
			expect(actual):toBe(nil)
		else
			local a, b = Queries.expectResult(actual), Queries.expectResult(expected)
			expect(a.Instance):toBe(b.Instance)
			expect(a.Position):toEqual(b.Position)
			expect(a.Normal):toEqual(b.Normal)
			expect(a.Distance):toBe(b.Distance)
			expect(a.Material):toBe(b.Material)
		end
	else
		expect(actual):toEqual(expected)
	end
end

for _, initialSeed in { 1709, 913, 4103 } do
	it(
		"matches the scan through movement resizing hierarchy and filters with seed " .. tostring(initialSeed),
		function()
			local engine, world, scan, indexed, counts = fixture()
			local seed = initialSeed
			local function random(n: number): number
				seed = (seed * 48271) % 2147483647
				return seed % n
			end
			local folder, detached, nested =
				engine.newInstance "Folder", engine.newInstance "Folder", engine.newInstance "WorldModel"
			folder.Parent, nested.Parent = world, world
			local parts: { E.Instance } = {}
			local function add(): E.Instance
				local part = engine.newInstance "Part"
				local size = 1 + random(6)
				part.Size = V.one * size
				part.Shape = if random(3) == 0 then D.Enum.PartType.Ball else D.Enum.PartType.Block
				part.CFrame = CF.new(random(61) - 30, random(11) - 5, random(61) - 30)
					* CF.Angles(random(100) / 100, random(100) / 100, random(100) / 100)
				part.Parent = if random(2) == 0 then folder else world
				table.insert(parts, part)
				return part
			end
			for _ = 1, 80 do
				add()
			end
			local source = engine.newInstance "Part"
			source.Size, source.Parent = V.one * 2, world
			local ray, overlap = D.RaycastParams.new(), D.OverlapParams.new()
			local observedHits, refusals = 0, 0
			for step = 1, 120 do
				local part = parts[1 + random(#parts)]
				local action = step % 10
				if action == 0 then
					part.Position = V.new(random(61) - 30, random(11) - 5, random(61) - 30)
				elseif action == 1 then
					part.Size = V.one * (1 + random(8))
				elseif action == 2 then
					part.CFrame = CF.new(random(61) - 30, 0, random(61) - 30) * CF.Angles(0.3, 0.7, 0.2)
				elseif action == 3 then
					part.Parent = ({ world, folder, detached, nested })[1 + random(4)]
				elseif action == 4 then
					folder.Parent = if folder.Parent then nil else world
				elseif action == 5 then
					part.CanQuery, part.CanCollide = random(2) == 0, random(2) == 0
				elseif action == 6 then
					part.CollisionGroup = if random(2) == 0 then "Hidden" else "Default"
				elseif action == 7 then
					part:Destroy()
					table.remove(parts, assert(table.find(parts, part)))
					part = add()
				elseif action == 8 then
					local clone = assert(part:Clone())
					clone.Parent = world
					table.insert(parts, clone)
				else
					part.Material = D.Enum.Material.Wood
				end
				local cf = Frames.expect(part.CFrame, 1)
				source.CFrame = cf + V.new(0, if step % 2 == 0 then 12 else 0, 0)
				for _, params in { ray, overlap } do
					params.FilterType = if step % 3 == 0
						then D.Enum.RaycastFilterType.Include
						else D.Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = if step % 4 == 0 then { folder } else {}
					params.IncludeInstances = if step % 5 == 0 then { world } else nil
					params.ExcludeInstances = { source }
					params.RespectCanCollide = step % 2 == 0
					params.BruteForceAllSlow = step % 7 == 0
					params.CollisionGroup = if step % 3 == 0 then "Sensor" else "Default"
				end
				ray.IgnoreWater, overlap.MaxParts = step % 2 == 0, step % 4
				local origin = Frames.expect(source.CFrame, 1).Position
				local direction = V.new(random(7) - 3, -25, random(7) - 3)
				for _, method in methods do
					local function query(callback: E.InstanceMethod): unknown
						if method == "Raycast" then
							return (callback(world, origin, direction, ray))
						elseif method == "Blockcast" then
							return (callback(world, source.CFrame, source.Size, direction, ray))
						elseif method == "Spherecast" then
							return (callback(world, origin, 1, direction, ray))
						elseif method == "Shapecast" then
							return (callback(world, source, direction, ray))
						elseif method == "GetPartBoundsInBox" then
							return (callback(world, source.CFrame, V.one * 5, overlap))
						elseif method == "GetPartBoundsInRadius" then
							return (callback(world, origin, 3, overlap))
						end
						return (callback(world, source, overlap))
					end
					local actualOk, actual = pcall(query, indexed[method])
					local expectedOk, expected = pcall(query, scan[method])
					expect(actualOk):toBe(expectedOk)
					if actualOk then
						compare(method, actual, expected)
						if
							actual ~= nil and (method == "Raycast" or method == "Spherecast" or method == "Shapecast")
						then
							observedHits += 1
						end
					else
						expect(tostring(actual)):toBe(tostring(expected))
						refusals += 1
					end
				end
			end
			expect(observedHits > 10):toBe(true)
			expect(refusals < 30):toBe(true)
			expect(counts.scan > counts.indexed * 5):toBe(true)
		end
	)
end

it("preserves descendant tie order after same-world reparenting and during hierarchy events", function()
	local engine, world, scan, indexed = fixture()
	local first, second = engine.newInstance "Folder", engine.newInstance "Folder"
	first.Parent, second.Parent = world, world
	local a, b = engine.newInstance "Part", engine.newInstance "Part"
	a.Size, b.Size, a.Parent, b.Parent = V.one * 2, V.one * 2, first, second
	local function check(): E.Instance
		local actual = indexed.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0))
		compare("Raycast", actual, scan.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0)))
		for _, method in { "GetPartBoundsInBox", "GetPartBoundsInRadius" } do
			local params = D.OverlapParams.new()
			params.MaxParts = 1
			if method == "GetPartBoundsInBox" then
				compare(
					method,
					indexed[method](world, CF.identity, V.one, params),
					scan[method](world, CF.identity, V.one, params)
				)
			else
				compare(method, indexed[method](world, V.zero, 1, params), scan[method](world, V.zero, 1, params))
			end
		end
		return Queries.expectResult(actual).Instance
	end
	expect(check()):toBe(a)
	local duringRemoval, duringAddition = 0, 0
	first.DescendantRemoving:Connect(function()
		check()
		duringRemoval += 1
	end)
	second.ChildAdded:Connect(function()
		check()
		duringAddition += 1
	end)
	a.Parent = second
	expect(check()):toBe(b)
	expect(duringRemoval):toBe(1)
	expect(duringAddition):toBe(1)
	local nearer = engine.newInstance "Part"
	nearer.Position, nearer.Size = V.new(0, 5, 0), V.one * 2
	world.ChildAdded:Connect(function()
		expect(check()):toBe(nearer)
	end)
	nearer.Parent = world
	expect(check()):toBe(nearer)
	expect(#engine.environment.errors):toBe(0)
end)

it("keeps distant unsupported geometry and terrain refusal paths visible", function()
	local engine, world, scan, indexed = fixture()
	local target = engine.newInstance "Part"
	target.Parent = world
	local invalid = engine.newInstance "WedgePart"
	invalid.Position, invalid.Parent = V.new(10000, 10000, 10000), world
	local function check()
		local function ray(callback: E.InstanceMethod): unknown
			return (callback(world, V.new(0, 10, 0), V.new(0, -20, 0)))
		end
		local a, actual = pcall(ray, indexed.Raycast)
		local b, expected = pcall(ray, scan.Raycast)
		expect(a):toBe(false)
		expect(a):toBe(b)
		expect(tostring(actual)):toBe(tostring(expected))
	end
	check()
	invalid:Destroy()
	local distant = engine.newInstance "Part"
	distant.Position, distant.Size, distant.Parent = V.new(10000, 10000, 10000), V.new(2, 2, 4), world
	indexed.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0))
	distant.Shape = D.Enum.PartType.Ball
	check()
	distant.Shape = D.Enum.PartType.Block
	local terrain = engine.environment.createEngineInstance "Terrain"
	terrain.Parent = world
	check()
	engine.environment.poke(terrain, "CFrame", CF.new(0, 5, 0))
	engine.environment.poke(terrain, "Size", V.one * 2)
	engine.environment.poke(terrain, "Material", D.Enum.Material.Water)
	for _, ignore in { false, true } do
		local params = D.RaycastParams.new()
		params.IgnoreWater = ignore
		compare(
			"Raycast",
			indexed.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0), params),
			scan.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0), params)
		)
	end
	engine.environment.method(terrain, "FillBlock")(terrain, CF.new(0, 5, 0), V.one * 2, D.Enum.Material.Water)
	engine.environment.method(terrain, "FillBall")(terrain, V.zero, 1, D.Enum.Material.Slate)
	for _, ignore in { false, true } do
		local params = D.RaycastParams.new()
		params.IgnoreWater = ignore
		compare(
			"Raycast",
			indexed.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0), params),
			scan.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0), params)
		)
	end
	engine.environment.method(terrain, "Clear")(terrain)
	compare(
		"Raycast",
		indexed.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0)),
		scan.Raycast(world, V.new(0, 10, 0), V.new(0, -20, 0))
	)
end)

it("keeps the narrow phase bounded when unrelated parts are added", function(own)
	local engine = Lute.fixture.bridge().placeEngine()
	local env, world = engine.environment, engine.service "Workspace"
	local count = 0
	local ray, cast, overlaps = Geometry.ray, Geometry.cast, Geometry.overlaps
	own(function()
		Geometry.ray, Geometry.cast, Geometry.overlaps = ray, cast, overlaps
	end)
	Geometry.ray = function(...)
		count += 1
		return ray(...)
	end
	Geometry.cast = function(...)
		count += 1
		return cast(...)
	end
	Geometry.overlaps = function(...)
		count += 1
		return overlaps(...)
	end
	local target, source = engine.newInstance "Part", engine.newInstance "Part"
	target.Size, target.Parent = V.one * 4, world
	source.Size, source.CFrame, source.Parent = V.one, CF.new(0, 10, 0), world
	local function check()
		local params = D.RaycastParams.new()
		params.ExcludeInstances = { source }
		for _, method in methods do
			count = 0
			local query = env.method(world, method)
			if method == "Raycast" then
				query(world, V.new(0, 10, 0), V.new(0, -20, 0), params)
			elseif method == "Blockcast" then
				query(world, CF.new(0, 10, 0), V.one, V.new(0, -20, 0), params)
			elseif method == "Spherecast" then
				query(world, V.new(0, 10, 0), 1, V.new(0, -20, 0), params)
			elseif method == "Shapecast" then
				query(world, source, V.new(0, -20, 0), params)
			elseif method == "GetPartBoundsInBox" then
				query(world, CF.identity, V.one)
			elseif method == "GetPartBoundsInRadius" then
				query(world, V.zero, 1)
			else
				query(world, target)
			end
			expect(count <= 1):toBeTrueWith(method .. " narrow phase count " .. tostring(count))
		end
	end
	check()
	for i = 1, 1000 do
		local part = engine.newInstance "Part"
		part.Position, part.Parent = V.new(100 + i * 4, 100, 100), world
	end
	check()
	target.Position = V.new(1000, 0, 0)
	check()
end)

return nil
