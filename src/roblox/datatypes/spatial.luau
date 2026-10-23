--!strict

local CFrame = require "./cframe"
local Names = require "./names"
local Vector = require "./vector"

type Vector3 = Vector.Vector3Value
export type RayValue = {
	Origin: Vector3,
	Direction: Vector3,
	Unit: RayValue,
	ClosestPoint: (RayValue, Vector3) -> Vector3,
	Distance: (RayValue, Vector3) -> number,
}
export type Region3Value = {
	CFrame: CFrame.CFrameValue,
	Size: Vector3,
	ExpandToGrid: (Region3Value, number) -> Region3Value,
}

local RayKind = Names.behavior "Ray"
local RegionKind = Names.behavior "Region3"

local function vector(value: unknown, position: number): Vector3
	if Names.of(value) ~= "Vector3" then
		Names.argument(position, "Vector3", value)
	end
	return value :: Vector3
end

local function ray(origin: Vector3?, direction: Vector3?): RayValue
	return Names.make(RayKind, {
		Origin = if origin == nil then Vector.Vector3.zero else vector(origin, 1),
		Direction = if direction == nil then Vector.Vector3.zero else vector(direction, 2),
	})
end

local function region(minimum: Vector3, maximum: Vector3): Region3Value
	local low, high = vector(minimum, 1), vector(maximum, 2)
	return Names.make(RegionKind, { CFrame = CFrame.CFrame.new((low + high) / 2), Size = high - low })
end

local function closest(self: RayValue, point: Vector3): Vector3
	local target = vector(point, 1)
	local lengthSquared = self.Direction:Dot(self.Direction)
	if lengthSquared == 0 then
		return self.Origin
	end
	return self.Origin + self.Direction * math.max(0, (target - self.Origin):Dot(self.Direction) / lengthSquared)
end

local rayMethods: { [string]: unknown } = {
	ClosestPoint = closest,
	Distance = function(self: RayValue, point: Vector3): number
		return (vector(point, 1) - closest(self, point)).Magnitude
	end,
}
RayKind.fields.__index = function(fields: Names.Fields, key: unknown): unknown
	if key == "Unit" then
		return ray(fields.Origin :: Vector3, (fields.Direction :: Vector3).Unit)
	end
	return rayMethods[key :: string] or Names.missing(RayKind, key)
end
RayKind.meta.__eq = function(a: RayValue, b: RayValue): boolean
	return a.Origin == b.Origin and a.Direction == b.Direction
end
RayKind.meta.__tostring = function(value: RayValue): string
	return "{" .. tostring(value.Origin) .. "}, {" .. tostring(value.Direction) .. "}"
end

local function expand(self: Region3Value, resolution: number): Region3Value
	assert(
		type(resolution) == "number" and resolution > 0 and resolution < math.huge,
		"resolution must be positive and finite"
	)
	local low, high = self.CFrame.Position - self.Size / 2, self.CFrame.Position + self.Size / 2
	return region((low / resolution):Floor() * resolution, (high / resolution):Ceil() * resolution)
end
RegionKind.fields.__index = function(_: Names.Fields, key: unknown): unknown
	if key == "ExpandToGrid" then
		return expand
	end
	return Names.missing(RegionKind, key)
end
RegionKind.meta.__eq = function(a: Region3Value, b: Region3Value): boolean
	return a.CFrame == b.CFrame and a.Size == b.Size
end

return {
	Ray = { new = ray },
	Region3 = { new = region },
}
