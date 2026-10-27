--!strict

local Datatypes = require "./datatypes"
local FrameTypes = require "./datatypes/cframe"
local VectorTypes = require "./datatypes/vector"
local Environment = require "./environment-types"
local ModelScale = require "./model-scale-fakes"

type Instance = Environment.Instance
type CFrame = Datatypes.CFrameValue
type Vector3 = Datatypes.Vector3Value

local NEAR = 0.1

local function attach(environment: Environment.Environment, hasPivot: (Instance) -> boolean)
	local function frame(object: Instance, property: string): CFrame
		local value = environment.propertyOf(object, property)
		assert(Datatypes.typeName(value) == "CFrame", property .. " must be a CFrame")
		return FrameTypes.expect(value, 1)
	end
	local function bounds(model: Instance, basis: CFrame): (CFrame, Vector3)
		local minimum = Datatypes.Vector3.new(math.huge, math.huge, math.huge)
		local maximum = -minimum
		local count = 0
		for _, object in model:GetDescendants() do
			if not object:IsA "BasePart" then
				continue
			end
			count += 1
			local localFrame = basis:Inverse() * frame(object, "CFrame")
			local half = VectorTypes.expect3(environment.propertyOf(object, "Size"), 1) / 2
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local corner = localFrame * Datatypes.Vector3.new(x * half.X, y * half.Y, z * half.Z)
						minimum = minimum:Min(corner)
						maximum = maximum:Max(corner)
					end
				end
			end
		end
		if count == 0 then
			return basis, Datatypes.Vector3.zero
		end
		return basis * Datatypes.CFrame.new((minimum + maximum) / 2), maximum - minimum
	end

	local function pivot(object: Instance): CFrame
		if object:IsA "BasePart" then
			return frame(object, "CFrame") * frame(object, "PivotOffset")
		end
		local primary = environment.propertyOf(object, "PrimaryPart") :: Instance?
		if primary then
			return pivot(primary)
		elseif hasPivot(object) then
			return frame(object, "WorldPivot")
		end
		local basis, volume = Datatypes.CFrame.identity, -1
		for _, child in object:GetDescendants() do
			if child:IsA "BasePart" then
				local size = VectorTypes.expect3(environment.propertyOf(child, "Size"), 1)
				local candidate = size.X * size.Y * size.Z
				if candidate > volume then
					basis, volume = frame(child, "CFrame").Rotation, candidate
				end
			end
		end
		local result = bounds(object, basis)
		return result
	end

	environment.fake("PVInstance.GetPivot", pivot)
	environment.fake("PVInstance.PivotTo", function(object: Instance, target: CFrame)
		assert(Datatypes.typeName(target) == "CFrame", "PivotTo requires a CFrame")
		if object:IsA "BasePart" then
			object.CFrame = target * frame(object, "PivotOffset"):Inverse()
			return
		end
		local delta = target * pivot(object):Inverse()
		for _, child in object:GetDescendants() do
			if child:IsA "BasePart" then
				child.CFrame = delta * frame(child, "CFrame")
			elseif child:IsA "Model" and hasPivot(child) then
				child.WorldPivot = delta * frame(child, "WorldPivot")
			end
		end
		object.WorldPivot = target
	end)
	environment.fake("Model.GetBoundingBox", function(object: Instance): (CFrame, Vector3)
		return bounds(object, pivot(object).Rotation)
	end)
	environment.fake("Model.GetExtentsSize", function(object: Instance): Vector3
		local _, size = bounds(object, pivot(object).Rotation)
		return size
	end)
	local function lens(camera: Instance): (CFrame, number, number, number)
		local viewport = VectorTypes.expect2(environment.propertyOf(camera, "ViewportSize"), 1)
		assert(viewport.X > 0 and viewport.Y > 0, "Camera.ViewportSize must be positive")
		local field = environment.propertyOf(camera, "FieldOfView")
		assert(type(field) == "number" and field > 0 and field < 180, "Camera.FieldOfView must be in (0, 180)")
		return frame(camera, "CFrame"), viewport.X, viewport.Y, math.tan(math.rad(field) / 2)
	end
	local function inset(camera: Instance): (number, number)
		local root = camera:FindFirstAncestorWhichIsA "DataModel"
		local service = root and root:FindFirstChildOfClass "GuiService"
		if service == nil then
			return 0, 0
		end
		local read: unknown = environment.propertyOf(service, "GetGuiInset")
		if type(read) ~= "function" then
			return 0, 0
		end
		local ok, topLeft = pcall(read :: (Instance) -> unknown, service)
		if not ok then
			return 0, 0
		end
		local corner = VectorTypes.expect2(topLeft, 1)
		return corner.X, corner.Y
	end
	local function project(camera: Instance, point: Vector3): (Vector3, boolean)
		assert(Datatypes.typeName(point) == "Vector3", "WorldToViewportPoint requires a Vector3")
		local basis, width, height, tangent = lens(camera)
		local relative = basis:PointToObjectSpace(point)
		local depth = -relative.Z
		local x = (relative.X / (math.abs(depth) * tangent * width / height) + 1) / 2 * width
		local y = (1 - relative.Y / (math.abs(depth) * tangent)) / 2 * height
		local visible = depth > 0 and x >= 0 and x <= width and y >= 0 and y <= height
		return Datatypes.Vector3.new(x, y, depth), visible
	end
	local function cast(camera: Instance, x: number, y: number, depth: number?): unknown
		assert(type(x) == "number" and type(y) == "number", "a viewport point needs numeric x and y")
		local basis, width, height, tangent = lens(camera)
		local reach = basis:VectorToWorldSpace(
			Datatypes.Vector3.new((2 * x / width - 1) * tangent * width / height, (1 - 2 * y / height) * tangent, -1)
		)
		local direction = reach.Unit
		local origin = basis.Position + reach * NEAR + direction * (depth or 0)
		return Datatypes.Ray.new(origin, direction)
	end
	environment.fake("Camera.WorldToViewportPoint", project)
	environment.fake("Camera.WorldToScreenPoint", function(camera: Instance, point: Vector3): (Vector3, boolean)
		local viewport, visible = project(camera, point)
		local left, top = inset(camera)
		return Datatypes.Vector3.new(viewport.X - left, viewport.Y - top, viewport.Z), visible
	end)
	environment.fake("Camera.ViewportPointToRay", cast)
	environment.fake(
		"Camera.ScreenPointToRay",
		function(camera: Instance, x: number, y: number, depth: number?): unknown
			local left, top = inset(camera)
			return cast(camera, x + left, y + top, depth)
		end
	)
	ModelScale.attach(environment, pivot)
end

return { attach = attach }
