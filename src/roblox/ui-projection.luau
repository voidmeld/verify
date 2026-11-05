--!strict

local Environment = require "./environment"
local Datatypes = require "./datatypes"
local Frames = require "./datatypes/cframe"
local Vectors = require "./datatypes/vector"
local Values = require "./ui-values"

type Instance = Environment.Instance
export type Point = { read X: number, read Y: number, read Z: number }
export type Basis = { read position: Point, read right: Point, read up: Point, read back: Point }
export type Camera = { basis: Basis, viewport: Values.Vector, fieldOfView: number }
export type Adornee = { read basis: Basis, read size: Point }
export type Host = {
	revision: () -> number,
	camera: () -> Camera?,
	adornee: (Instance) -> Adornee?,
}
export type Area = { x: number, y: number, width: number, height: number }

local function unsupported(object: Instance, mechanism: string): never
	error("unsupported_ui_layout: " .. object:GetFullName() .. " requires BillboardGui " .. mechanism, 0)
end

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function point(value: Point): boolean
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end

local function basis(value: Basis): boolean
	return point(value.position) and point(value.right) and point(value.up) and point(value.back)
end

local function dot(left: Point, right: Point): number
	return left.X * right.X + left.Y * right.Y + left.Z * right.Z
end

local function resolve(object: Instance, read: (Instance, string) -> unknown, host: Host?): Area?
	local function required(property: string, kind: string): unknown
		local value = read(object, property)
		if Datatypes.typeName(value) ~= kind then
			return unsupported(object, property)
		end
		return value
	end
	if read(object, "Enabled") == false then
		return nil
	end
	if host == nil then
		return unsupported(object, "host projection")
	end
	local camera = host.camera()
	if camera == nil then
		return unsupported(object, "CurrentCamera")
	end
	if
		not basis(camera.basis)
		or not finite(camera.viewport.X)
		or not finite(camera.viewport.Y)
		or camera.viewport.X <= 0
		or camera.viewport.Y <= 0
		or not finite(camera.fieldOfView)
		or camera.fieldOfView <= 0
		or camera.fieldOfView >= 180
	then
		return unsupported(object, "valid camera projection")
	end
	local target = read(object, "Adornee") or object.Parent
	if not Environment.isInstance(target) then
		return unsupported(object, "Adornee or parent part")
	end
	local adornee = host.adornee(Environment.assertInstance(target))
	if adornee == nil or not basis(adornee.basis) or not point(adornee.size) then
		return unsupported(object, "adornee position and bounds")
	end
	local authored = Values.dimensions(required("Size", "UDim2"))
	local offset = Values.vector(required("SizeOffset", "Vector2"))
	local studs = Vectors.expect3(required("StudsOffset", "Vector3"), 1)
	local extents = Vectors.expect3(required("ExtentsOffset", "Vector3"), 1)
	local world = Vectors.expect3(required("StudsOffsetWorldSpace", "Vector3"), 1)
	local worldExtents = Vectors.expect3(required("ExtentsOffsetWorldSpace", "Vector3"), 1)
	local onTop, light, maximum =
		read(object, "AlwaysOnTop"), read(object, "LightInfluence"), read(object, "MaxDistance")
	if
		not finite(authored.X.Scale)
		or not finite(authored.Y.Scale)
		or not finite(authored.X.Offset)
		or not finite(authored.Y.Offset)
		or not finite(offset.X)
		or not finite(offset.Y)
		or not point(studs)
		or not point(extents)
		or not point(world)
		or not point(worldExtents)
		or type(onTop) ~= "boolean"
		or type(light) ~= "number"
		or not finite(light)
		or light < 0
		or light > 1
		or type(maximum) ~= "number"
		or maximum ~= maximum
		or maximum < 0
	then
		return unsupported(object, "valid projection properties")
	end
	local limits: { [string]: number } = { DistanceLowerLimit = 0, DistanceUpperLimit = -1 }
	for property, default in limits do
		local value = read(object, property)
		if value ~= nil and value ~= default then
			unsupported(object, property)
		end
	end
	local function half(axis: Point): number
		return (
			math.abs(dot(axis, adornee.basis.right)) * adornee.size.X
			+ math.abs(dot(axis, adornee.basis.up)) * adornee.size.Y
			+ math.abs(dot(axis, adornee.basis.back)) * adornee.size.Z
		) / 2
	end
	local position = adornee.basis.position
	local eye = camera.basis.position
	local dx, dy, dz = position.X - eye.X, position.Y - eye.Y, position.Z - eye.Z
	local worldOffset = {
		X = world.X + worldExtents.X * half { X = 1, Y = 0, Z = 0 },
		Y = world.Y + worldExtents.Y * half { X = 0, Y = 1, Z = 0 },
		Z = world.Z + worldExtents.Z * half { X = 0, Y = 0, Z = 1 },
	}
	local function relative(axis: Point, stud: number, extent: number): number
		return dx * axis.X + dy * axis.Y + dz * axis.Z + dot(worldOffset, axis) + stud + extent * half(axis)
	end
	local z = relative(camera.basis.back, studs.Z, extents.Z)
	local depth = -z
	if depth <= 0 or maximum > 0 and depth > maximum then
		return { x = 0, y = 0, width = 0, height = 0 }
	end
	local pixels = camera.viewport.Y / (2 * math.tan(math.rad(camera.fieldOfView) / 2) * depth)
	return {
		x = 0,
		y = 0,
		width = math.max(0, math.round(authored.X.Scale * pixels + authored.X.Offset)),
		height = math.max(0, math.round(authored.Y.Scale * pixels + authored.Y.Offset)),
	}
end

local function fixture(environment: Environment.Environment, currentCamera: () -> Instance?): Host
	local function frame(value: unknown): Basis?
		if Datatypes.typeName(value) ~= "CFrame" then
			return nil
		end
		local valueFrame = Frames.expect(value, 1)
		return {
			position = valueFrame.Position,
			right = valueFrame.RightVector,
			up = valueFrame.UpVector,
			back = valueFrame.ZVector,
		}
	end
	return {
		revision = function(): number
			local revision = environment.revision()
			return revision
		end,
		camera = function(): Camera?
			local camera = currentCamera()
			if camera == nil or not camera:IsA "Camera" then
				return nil
			end
			local cameraFrame = frame(environment.propertyOf(camera, "CFrame"))
			local viewport = environment.propertyOf(camera, "ViewportSize")
			local field = environment.propertyOf(camera, "FieldOfView")
			if cameraFrame == nil or Datatypes.typeName(viewport) ~= "Vector2" or type(field) ~= "number" then
				return nil
			end
			return { basis = cameraFrame, viewport = Values.vector(viewport), fieldOfView = field }
		end,
		adornee = function(object: Instance): Adornee?
			if not environment.isAlive(object) or not object:IsA "BasePart" then
				return nil
			end
			local objectFrame = frame(environment.propertyOf(object, "CFrame"))
			local size = environment.propertyOf(object, "Size")
			if objectFrame == nil or Datatypes.typeName(size) ~= "Vector3" then
				return nil
			end
			return { basis = objectFrame, size = Vectors.expect3(size, 1) }
		end,
	}
end

return { resolve = resolve, fixture = fixture }
