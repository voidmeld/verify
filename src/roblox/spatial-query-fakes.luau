--!strict

local Datatypes = require "./datatypes"
local FrameTypes = require "./datatypes/cframe"
local VectorTypes = require "./datatypes/vector"
local EnumTypes = require "./datatypes/enum"
local Names = require "./datatypes/names"
local Environment = require "./environment-types"

type Instance = Environment.Instance
type Vector = Datatypes.Vector3Value
type Result = { Instance: Instance, Position: Vector, Normal: Vector, Distance: number, Material: unknown }

local resultKind = Names.behavior "RaycastResult"
local axes = { Datatypes.Vector3.xAxis, Datatypes.Vector3.yAxis, Datatypes.Vector3.zAxis }

local function listed(part: Instance, filter: { unknown }): boolean
	for _, candidate in filter do
		assert(Names.kind(candidate) == "Instance", "raycast filters require Instances")
		local object = candidate :: Instance
		if part == object or part:IsDescendantOf(object) then
			return true
		end
	end
	return false
end

local function box(origin: Vector, direction: Vector, half: Vector): (number?, Vector?)
	local origins, directions, sizes =
		{ origin.X, origin.Y, origin.Z }, { direction.X, direction.Y, direction.Z }, { half.X, half.Y, half.Z }
	local near, far = -math.huge, math.huge
	local normal = Datatypes.Vector3.zero
	for index = 1, 3 do
		local offset, delta, size = origins[index], directions[index], sizes[index]
		if delta == 0 then
			if offset < -size or offset > size then
				return nil, nil
			end
		else
			local first, last = (-size - offset) / delta, (size - offset) / delta
			local face = -axes[index]
			if first > last then
				first, last, face = last, first, axes[index]
			end
			if first > near then
				near, normal = first, face
			end
			far = math.min(far, last)
			if near > far then
				return nil, nil
			end
		end
	end
	return if near >= 0 and near <= 1 then near else nil, normal
end

local function attach(environment: Environment.Environment)
	environment.fake(
		"WorldRoot.Raycast",
		function(world: Instance, origin: Vector, direction: Vector, supplied: Datatypes.RaycastParamsValue?): Result?
			assert(
				Datatypes.typeName(origin) == "Vector3" and Datatypes.typeName(direction) == "Vector3",
				"raycast requires Vector3 origin and direction"
			)
			for _, value in { origin.X, origin.Y, origin.Z, direction.X, direction.Y, direction.Z } do
				assert(value == value and math.abs(value) < math.huge, "raycast vectors must be finite")
			end
			local params = supplied or Datatypes.RaycastParams.new()
			assert(Datatypes.typeName(params) == "RaycastParams", "raycast requires RaycastParams")
			assert(params.CollisionGroup == "Default", "raycast collision-group rules require an explicit host")
			local length = direction.Magnitude
			if length == 0 then
				return nil
			end
			local nearest: Result? = nil
			for _, part in world:GetDescendants() do
				if not part:IsA "BasePart" or part:IsA "Terrain" then
					continue
				end
				local legacy = listed(part, params.FilterDescendantsInstances)
				if
					(params.FilterType.Name == "Include" and not legacy)
					or (params.FilterType.Name == "Exclude" and legacy)
				then
					continue
				end
				if params.IncludeInstances ~= nil and not listed(part, params.IncludeInstances) then
					continue
				end
				if params.ExcludeInstances ~= nil and listed(part, params.ExcludeInstances) then
					continue
				end
				local collidable = environment.propertyOf(part, "CanCollide") == true
				if
					not params.BruteForceAllSlow
					and (
						if params.RespectCanCollide
							then not collidable
							else not collidable and environment.propertyOf(part, "CanQuery") ~= true
					)
				then
					continue
				end
				assert(
					environment.propertyOf(part, "CollisionGroup") == "Default",
					"raycast collision-group rules require an explicit host"
				)
				assert(
					part.ClassName == "Part"
						and EnumTypes.itemValue(environment.propertyOf(part, "Shape")).Name == "Block",
					"raycast collision geometry requires an explicit host for " .. part.ClassName
				)
				local frame = FrameTypes.expect(environment.propertyOf(part, "CFrame"), 1)
				local size = VectorTypes.expect3(environment.propertyOf(part, "Size"), 1)
				local fraction, normal =
					box(frame:PointToObjectSpace(origin), frame:VectorToObjectSpace(direction), size / 2)
				if fraction ~= nil and (nearest == nil or fraction * length < nearest.Distance) then
					nearest = Names.make(resultKind, {
						Instance = part,
						Position = origin + direction * fraction,
						Normal = frame:VectorToWorldSpace(assert(normal)),
						Distance = fraction * length,
						Material = environment.propertyOf(part, "Material"),
					})
				end
			end
			return nearest
		end
	)
end

return { attach = attach }
