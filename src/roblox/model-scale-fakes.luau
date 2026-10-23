--!strict

local Types = require "./datatypes"
local Environment = require "./environment-types"

type Instance = Environment.Instance
type CFrame = Types.CFrameValue
type Vector3 = Types.Vector3Value
type Cached = { original: unknown, written: unknown }
type Write = { object: Instance, property: string, value: unknown, original: unknown }

local function weaken(cache: { [Instance]: { [string]: Cached } })
	setmetatable(cache, { __mode = "k" })
end

local fields: { [string]: { string } } = {
	BasePart = { "Size", "PivotOffset" },
	Attachment = { "CFrame" },
	JointInstance = { "C0", "C1" },
	DataModelMesh = { "Offset" },
	Sound = { "RollOffMinDistance", "RollOffMaxDistance" },
	ParticleEmitter = { "Size", "Speed", "Acceleration" },
	Beam = { "Width0", "Width1", "CurveSize0", "CurveSize1" },
	Trail = { "MinLength", "MaxLength" },
	Humanoid = { "HipHeight", "WalkSpeed", "JumpHeight" },
	RopeConstraint = { "Length", "Thickness" },
}

local function scaled(value: unknown, ratio: number): unknown
	if type(value) == "number" then
		return value * ratio
	end
	local kind = Types.typeName(value)
	if kind == "Vector3" then
		return (value :: Vector3) * ratio
	elseif kind == "CFrame" then
		local frame = value :: CFrame
		return Types.CFrame.new(frame.Position * ratio) * frame.Rotation
	elseif kind == "NumberRange" then
		local range = value :: Types.NumberRangeValue
		return Types.NumberRange.new(range.Min * ratio, range.Max * ratio)
	elseif kind == "NumberSequence" then
		local points: { Types.NumberSequenceKeypointValue } = {}
		for _, point in (value :: Types.NumberSequenceValue).Keypoints do
			table.insert(
				points,
				Types.NumberSequenceKeypoint.new(point.Time, point.Value * ratio, point.Envelope * ratio)
			)
		end
		return Types.NumberSequence.new(points)
	end
	error("unsupported_model_scale_value: " .. tostring(kind))
end

local function attach(environment: Environment.Environment, pivot: (Instance) -> CFrame)
	local scales = setmetatable({} :: { [Instance]: number }, { __mode = "k" })
	local originals = setmetatable({} :: { [Instance]: { [Instance]: { [string]: Cached } } }, { __mode = "k" })
	environment.fake("Model.GetScale", function(model: Instance): number
		return scales[model] or 1
	end)
	environment.fake("Model.ScaleTo", function(model: Instance, scale: number)
		assert(type(scale) == "number" and scale > 0 and scale < math.huge, "ScaleTo requires a positive finite scale")
		local previous = scales[model] or 1
		if scale == previous then
			return
		end
		local ratio, origin = scale / previous, pivot(model)
		local modelCache = originals[model] or {}
		weaken(modelCache)
		originals[model] = modelCache
		local writes: { Write } = {}
		local models = { model }
		local function enqueue(object: Instance, property: string, value: unknown, original: unknown?)
			table.insert(writes, { object = object, property = property, value = value, original = original })
		end
		local function resize(object: Instance, property: string, exponent: number?)
			local value = environment.propertyOf(object, property)
			if value == nil then
				return
			end
			local power = exponent or 1
			local cache = modelCache[object]
			local entry = if cache then cache[property] else nil
			local original = if entry and entry.written == value
				then entry.original
				else scaled(value, previous ^ -power)
			enqueue(object, property, scaled(original, scale ^ power), original)
		end
		for _, object in model:GetDescendants() do
			if object:IsA "Constraint" and not object:IsA "RopeConstraint" then
				error("unsupported_model_scale_constraint: " .. object.ClassName)
			end
			if object:IsA "BasePart" then
				local frame = environment.propertyOf(object, "CFrame") :: CFrame
				enqueue(
					object,
					"CFrame",
					Types.CFrame.new(origin.Position + (frame.Position - origin.Position) * ratio) * frame.Rotation
				)
			elseif object:IsA "Model" then
				table.insert(models, object)
				local frame = pivot(object)
				enqueue(
					object,
					"WorldPivot",
					Types.CFrame.new(origin.Position + (frame.Position - origin.Position) * ratio) * frame.Rotation
				)
			end
			for class, properties in fields do
				if object:IsA(class) then
					for _, property in properties do
						resize(object, property)
					end
				end
			end
			if object:IsA "Humanoid" then
				resize(object, "JumpPower", 0.5)
			elseif object:IsA "SpecialMesh" then
				local meshType = environment.propertyOf(object, "MeshType") :: Types.EnumMember
				if meshType.Name == "FileMesh" then
					resize(object, "Scale")
				end
			end
		end
		for _, write in writes do
			local object, property = write.object, write.property
			object[property] = write.value
			if write.original ~= nil then
				local cache = modelCache[object] or {}
				modelCache[object] = cache
				cache[property] = { original = write.original, written = write.value }
			end
		end
		for _, object in models do
			scales[object] = (scales[object] or 1) * ratio
		end
		model.WorldPivot = origin
	end)
	environment.onClone(function(source: Instance, copy: Instance)
		scales[copy] = scales[source]
	end)
end

return { attach = attach }
