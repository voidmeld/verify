--!strict

local Datatypes = require "./datatypes"
local Environment = require "./environment-types"

type Instance = Environment.Instance
type CFrame = Datatypes.CFrameValue
type Vector3 = Datatypes.Vector3Value

local function attach(environment: Environment.Environment, hasPivot: (Instance) -> boolean)
	local function frame(object: Instance, property: string): CFrame
		local value = environment.propertyOf(object, property)
		assert(Datatypes.typeName(value) == "CFrame", property .. " must be a CFrame")
		return value :: CFrame
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
			local half = (environment.propertyOf(object, "Size") :: Vector3) / 2
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
				local size = environment.propertyOf(child, "Size") :: Vector3
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
end

return { attach = attach }
