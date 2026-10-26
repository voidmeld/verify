--!strict

local D = require "./datatypes"
local Frames = require "./datatypes/cframe"
local Vectors = require "./datatypes/vector"
local Enums = require "./datatypes/enum"
local Names = require "./datatypes/names"
local Environment = require "./environment-types"
local Geometry = require "./query-geometry"

type Instance = Environment.Instance
type Vector = D.Vector3Value
type Frame = D.CFrameValue
type Shape = Geometry.Shape
type Filter = D.RaycastParamsValue | D.OverlapParamsValue
type Result = { Instance: Instance, Position: Vector, Normal: Vector, Distance: number, Material: unknown }
local resultKind = Names.behavior "RaycastResult"
local V = D.Vector3

local function finite(value: number)
	assert(value == value and math.abs(value) < math.huge, "query values must be finite")
end

local function vector(value: Vector): Vector
	assert(D.typeName(value) == "Vector3", "query requires Vector3")
	finite(value.X)
	finite(value.Y)
	finite(value.Z)
	return value
end

local function frame(value: Frame): Frame
	assert(D.typeName(value) == "CFrame", "query requires CFrame")
	for _, n in { value:GetComponents() } do
		finite(n)
	end
	local x, y, z = value.RightVector, value.UpVector, value.ZVector
	assert(
		math.abs(x.Magnitude - 1) < 0.0001
			and math.abs(y.Magnitude - 1) < 0.0001
			and math.abs(z.Magnitude - 1) < 0.0001
			and math.abs(x:Dot(y)) < 0.0001
			and (x:Cross(y) - z).Magnitude < 0.0001,
		"unsupported: query requires an orthonormal CFrame"
	)
	return value
end

local function box(cf: Frame, size: Vector): Shape
	vector(size)
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "query size must be positive")
	return { frame = frame(cf), half = size / 2 }
end

local function ball(position: Vector, radius: number): Shape
	vector(position)
	finite(radius)
	assert(radius >= 0, "query radius must be nonnegative")
	return { frame = D.CFrame.new(position), half = V.one * radius, radius = radius }
end

local function listed(part: Instance, filter: { unknown }): boolean
	for _, candidate in filter do
		assert(Names.kind(candidate) == "Instance", "query filters require Instances")
		local object = candidate :: Instance
		if part == object or part:IsDescendantOf(object) then
			return true
		end
	end
	return false
end

local function attach(environment: Environment.Environment)
	type Rules = { groups: { [string]: boolean }, masks: { [string]: { [string]: boolean } } }
	local worlds = setmetatable({} :: { [Instance]: Rules }, { __mode = "k" })
	local function rules(owner: Instance): Rules
		local world = owner
		if owner:IsA "PhysicsService" or owner:IsA "Workspace" then
			world = environment.root
		end
		if not worlds[world] then
			worlds[world] = { groups = { Default = true }, masks = {} }
		end
		return worlds[world]
	end
	local function collidable(owner: Instance, a: string, b: string): boolean
		local groups, masks = rules(owner).groups, rules(owner).masks
		return not (groups[a] and groups[b] and masks[a] and masks[a][b] == false)
	end
	local function register(owner: Instance, name: string)
		assert(type(name) == "string" and #name > 0, "collision group name must be nonempty")
		local groups = rules(owner).groups
		groups[name] = true
	end
	local function setCollidable(owner: Instance, a: string, b: string, enabled: boolean)
		local groups, masks = rules(owner).groups, rules(owner).masks
		assert(groups[a] and groups[b], "collision groups must be registered")
		assert(type(enabled) == "boolean", "collision status must be boolean")
		masks[a], masks[b] = masks[a] or {}, masks[b] or {}
		masks[a][b], masks[b][a] = enabled, enabled
	end
	for _, class in { "PhysicsService", "WorldRoot" } do
		environment.fake(class .. ".RegisterCollisionGroup", register)
		environment.fake(class .. ".IsCollisionGroupRegistered", function(owner: Instance, name: string): boolean
			return rules(owner).groups[name] == true
		end)
		environment.fake(class .. ".CollisionGroupSetCollidable", setCollidable)
		environment.fake(
			class .. ".CollisionGroupsAreCollidable",
			function(owner: Instance, a: string, b: string): boolean
				return collidable(owner, a, b)
			end
		)
		environment.fake(class .. ".UnregisterCollisionGroup", function(owner: Instance, name: string)
			local groups, masks = rules(owner).groups, rules(owner).masks
			assert(name ~= "Default", "cannot unregister Default")
			groups[name], masks[name] = nil, nil
			for _, mask in masks do
				mask[name] = nil
			end
		end)
	end
	local function shape(part: Instance, bounds: boolean): Shape
		assert(
			environment.isAlive(part) and (part:IsA "BasePart" or part:IsA "Terrain"),
			"query requires a live BasePart"
		)
		if part:IsA "Terrain" then
			assert(
				environment.propertyOf(part, "CFrame") ~= nil and environment.propertyOf(part, "Size") ~= nil,
				"unsupported_content: Terrain requires authored CFrame and Size bounds"
			)
		end
		local result = box(
			Frames.expect(environment.propertyOf(part, "CFrame"), 1),
			Vectors.expect3(environment.propertyOf(part, "Size"), 1)
		)
		if not bounds and part.ClassName == "Part" then
			local kind = Enums.itemValue(environment.propertyOf(part, "Shape")).Name
			assert(kind == "Block" or kind == "Ball" or kind == "Cylinder", "unsupported_content: Part shape " .. kind)
			if kind == "Ball" then
				assert(
					result.half.X == result.half.Y and result.half.Y == result.half.Z,
					"unsupported_content: nonuniform Ball collision geometry"
				)
				result.radius = result.half.X
			end
		elseif not bounds then
			assert(
				part:IsA "MeshPart"
					or part:IsA "Terrain"
					or part:IsA "PartOperation"
					or part:IsA "Seat"
					or part:IsA "SpawnLocation"
					or part.ClassName == "TrussPart",
				"unsupported_content: collision geometry for " .. part.ClassName
			)
		end
		return result
	end
	local function owningWorld(part: Instance): Instance?
		local parent = part.Parent
		while parent do
			if parent:IsA "WorldRoot" then
				return parent
			end
			parent = parent.Parent
		end
		return nil
	end
	local function candidates(world: Instance, params: Filter, skip: Instance?): { Instance }
		local found = {}
		for _, part in world:GetDescendants() do
			if part == skip or not (part:IsA "BasePart" or part:IsA "Terrain") or owningWorld(part) ~= world then
				continue
			end
			local legacy = listed(part, params.FilterDescendantsInstances)
			if
				(params.FilterType.Name == "Include" and not legacy) or (params.FilterType.Name == "Exclude" and legacy)
			then
				continue
			end
			if params.IncludeInstances ~= nil and not listed(part, params.IncludeInstances) then
				continue
			end
			if params.ExcludeInstances ~= nil and listed(part, params.ExcludeInstances) then
				continue
			end
			if not params.BruteForceAllSlow then
				local terrain = part:IsA "Terrain"
				local canCollide = terrain or environment.propertyOf(part, "CanCollide") == true
				if
					if params.RespectCanCollide
						then not canCollide
						else not canCollide and environment.propertyOf(part, "CanQuery") ~= true
				then
					continue
				end
				local group = if terrain then "Default" else environment.propertyOf(part, "CollisionGroup")
				assert(type(group) == "string", "query collision group must be a string")
				if not collidable(world, params.CollisionGroup, group) then
					continue
				end
			end
			table.insert(found, part)
		end
		return found
	end
	local function cast(
		world: Instance,
		source: Shape,
		direction: Vector,
		supplied: D.RaycastParamsValue?,
		skip: Instance?,
		isRay: boolean
	): Result?
		vector(direction)
		local params = supplied or D.RaycastParams.new()
		assert(D.typeName(params) == "RaycastParams", "cast requires RaycastParams")
		assert(
			params.Margin == 0 and params.SizeGradient == 0,
			"unsupported: cast Margin and SizeGradient must be zero"
		)
		local length = direction.Magnitude
		assert(length <= (if isRay then 15000 else 1024), "cast direction exceeds maximum distance")
		if not isRay then
			assert(
				source.half.X <= 256 and source.half.Y <= 256 and source.half.Z <= 256,
				"cast shape exceeds maximum size 512"
			)
		end
		local nearest: Result? = nil
		for _, part in candidates(world, params, skip) do
			if part:IsA "Terrain" then
				assert(
					environment.propertyOf(part, "Material") ~= nil,
					"unsupported_content: Terrain requires a uniform authored Material"
				)
			end
			if
				part:IsA "Terrain"
				and params.IgnoreWater
				and Enums.itemValue(environment.propertyOf(part, "Material")).Name == "Water"
			then
				continue
			end
			local target = shape(part, false)
			if length == 0 then
				continue
			end
			local t: number?, normal: Vector?, position: Vector?
			if isRay then
				t, normal, position = Geometry.ray(source, direction, target)
			else
				t, normal, position = Geometry.cast(source, direction, target)
			end
			if t ~= nil and (nearest == nil or t * length < nearest.Distance) then
				nearest = Names.make(resultKind, {
					Instance = part,
					Position = assert(position),
					Normal = assert(normal),
					Distance = t * length,
					Material = environment.propertyOf(part, "Material"),
				})
			end
		end
		return nearest
	end
	local function overlap(
		world: Instance,
		source: Shape,
		supplied: D.OverlapParamsValue?,
		skip: Instance?,
		bounds: boolean
	): { Instance }
		local params = supplied or D.OverlapParams.new()
		assert(D.typeName(params) == "OverlapParams", "overlap requires OverlapParams")
		assert(params.MaxParts >= 0, "MaxParts must be nonnegative")
		assert(params.Tolerance == 0, "unsupported: nonzero overlap Tolerance")
		local found = {}
		for _, part in candidates(world, params, skip) do
			if Geometry.overlaps(source, shape(part, bounds)) then
				table.insert(found, part)
			end
		end
		if params.MaxParts > 0 then
			while #found > params.MaxParts do
				table.remove(found)
			end
		end
		return found
	end
	environment.fake(
		"WorldRoot.Raycast",
		function(world: Instance, origin: Vector, direction: Vector, params: D.RaycastParamsValue?): Result?
			return cast(world, ball(origin, 0), direction, params, nil, true)
		end
	)
	environment.fake(
		"WorldRoot.Blockcast",
		function(world: Instance, cf: Frame, size: Vector, direction: Vector, params: D.RaycastParamsValue?): Result?
			return cast(world, box(cf, size), direction, params, nil, false)
		end
	)
	environment.fake(
		"WorldRoot.Spherecast",
		function(
			world: Instance,
			origin: Vector,
			radius: number,
			direction: Vector,
			params: D.RaycastParamsValue?
		): Result?
			assert(radius > 0, "Spherecast radius must be positive")
			return cast(world, ball(origin, radius), direction, params, nil, false)
		end
	)
	environment.fake(
		"WorldRoot.Shapecast",
		function(
			world: Instance,
			part: Instance,
			direction: Vector,
			params: D.RaycastParamsValue?,
			frameOverride: Frame?,
			sizeOverride: Vector?
		): Result?
			assert(frameOverride == nil and sizeOverride == nil, "unsupported: Shapecast overrides")
			assert(not part:IsA "Terrain", "unsupported_content: Shapecast cannot cast Terrain")
			return cast(world, shape(part, false), direction, params, part, false)
		end
	)
	environment.fake(
		"WorldRoot.GetPartBoundsInBox",
		function(world: Instance, cf: Frame, size: Vector, params: D.OverlapParamsValue?): { Instance }
			return overlap(world, box(cf, size), params, nil, true)
		end
	)
	environment.fake(
		"WorldRoot.GetPartBoundsInRadius",
		function(world: Instance, origin: Vector, radius: number, params: D.OverlapParamsValue?): { Instance }
			return overlap(world, ball(origin, radius), params, nil, true)
		end
	)
	environment.fake(
		"WorldRoot.GetPartsInPart",
		function(world: Instance, part: Instance, params: D.OverlapParamsValue?): { Instance }
			assert(owningWorld(part) == world, "GetPartsInPart source must be in the same WorldRoot")
			return overlap(world, shape(part, false), params, part, false)
		end
	)
end

return { attach = attach }
