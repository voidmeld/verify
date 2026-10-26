--!strict

local Environment = require "./environment-types"
local Datatypes = require "./datatypes"

export type Request = { kind: string, key: string, id: number?, version: number? }
export type Node = { [string]: unknown }
export type Row = { request: Request, ok: boolean, facts: { Node }?, refusal: string? }
export type Capture = {
	schemaVersion: number,
	engineVersion: string,
	placeId: number,
	placeVersion: number,
	gameId: number,
	rows: { Row },
}

local vectors: { [string]: string } = { size = "Size", meshSize = "MeshSize", scale = "Scale", offset = "Offset" }
local frames: { [string]: string | boolean } = {
	cframe = "CFrame",
	pivot = "WorldPivot",
	pivotOffset = "PivotOffset",
	box = false,
	c0 = "C0",
	c1 = "C1",
	transform = "Transform",
}
local references: { [string]: string } = {
	primaryPart = "PrimaryPart",
	part0 = "Part0",
	part1 = "Part1",
	attachment0 = "Attachment0",
	attachment1 = "Attachment1",
}
local scalars: { [string]: string } = {
	canCollide = "CanCollide",
	canQuery = "CanQuery",
	materialVariant = "MaterialVariant",
	meshId = "MeshId",
	textureId = "TextureID",
	colorMap = "ColorMap",
	normalMap = "NormalMap",
	metalnessMap = "MetalnessMap",
	roughnessMap = "RoughnessMap",
	loop = "Loop",
	time = "Time",
	weight = "Weight",
}
local maps: { [string]: string } = {
	colorMap = "ColorMapContent",
	normalMap = "NormalMapContent",
	metalnessMap = "MetalnessMapContent",
	roughnessMap = "RoughnessMapContent",
}
local enums: { [string]: { string } } = {
	material = { "Material", "Material" },
	collisionFidelity = { "CollisionFidelity", "CollisionFidelity" },
	alphaMode = { "AlphaMode", "AlphaMode" },
	priority = { "Priority", "AnimationPriority" },
	easingStyle = { "EasingStyle", "PoseEasingStyle" },
	easingDirection = { "EasingDirection", "PoseEasingDirection" },
}
local required: { [string]: { string } } = {
	Model = { "pivot", "box", "size" },
	BasePart = { "cframe", "pivotOffset", "size", "canCollide", "canQuery", "material", "materialVariant" },
	MeshPart = { "meshId", "textureId", "meshSize", "collisionFidelity" },
	SurfaceAppearance = { "colorMap", "normalMap", "metalnessMap", "roughnessMap", "alphaMode" },
	SpecialMesh = { "meshId", "textureId", "scale", "offset" },
	Attachment = { "cframe" },
	Bone = { "transform" },
	Motor6D = { "c0", "c1", "transform" },
	AnimationConstraint = { "transform" },
	KeyframeSequence = { "loop", "priority" },
	Keyframe = { "time" },
	Pose = { "cframe", "weight", "easingStyle", "easingDirection" },
}

local function requireFields(node: Node, fields: { string })
	for _, field in fields do
		assert(node[field] ~= nil, "missing content field: " .. field)
	end
end

local function record(value: unknown): { [string]: unknown }
	assert(type(value) == "table", "content facts require an object")
	return value :: { [string]: unknown }
end

local function integer(value: unknown, minimum: number): number
	assert(
		type(value) == "number" and value >= minimum and value <= 9007199254740991 and value % 1 == 0,
		"content facts require a safe integer"
	)
	return value
end

local function text(value: unknown): string
	assert(type(value) == "string" and value ~= "", "content facts require nonempty text")
	return value
end

local function array(value: unknown): { unknown }
	assert(type(value) == "table", "content facts require an array")
	local result = value :: { unknown }
	local count = 0
	for key in result do
		integer(key, 1)
		count += 1
	end
	assert(count == #result, "content facts require a dense array")
	return result
end

local function numbers(value: unknown, count: number): { number }
	local values = array(value)
	assert(#values == count, "content facts have the wrong component count")
	for _, component in values do
		assert(
			type(component) == "number" and component == component and math.abs(component) < math.huge,
			"content facts require finite components"
		)
	end
	return values :: { number }
end

local function requests(value: unknown): { Request }
	local rows = array(value)
	assert(#rows > 0, "content capture requires requests")
	local seen: { [string]: boolean } = {}
	for _, entry in rows do
		local row = record(entry)
		local kind, key = text(row.kind), text(row.key)
		assert(kind == "model" or kind == "mesh" or kind == "animation", "unknown content capture kind")
		assert(not seen[key], "duplicate content capture key")
		seen[key] = true
		integer(if kind == "model" then row.version else row.id, 1)
		assert(if kind == "model" then row.id == nil else row.version == nil, "content request has the wrong ID field")
		for field in row do
			assert(
				field == "kind" or field == "key" or field == "id" or field == "version",
				"unknown content request field"
			)
		end
	end
	return rows :: { Request }
end

local function validate(value: unknown): Capture
	local capture = record(value)
	assert(capture.schemaVersion == 1, "unsupported content capture schema")
	text(capture.engineVersion)
	integer(capture.placeId, 0)
	integer(capture.placeVersion, 0)
	integer(capture.gameId, 0)
	local rows = array(capture.rows)
	local inputs: { unknown } = {}
	for _, entry in rows do
		local row = record(entry)
		table.insert(inputs, row.request)
		assert(type(row.ok) == "boolean", "content capture requires a load result")
		if row.ok then
			assert(row.refusal == nil, "successful content capture has a refusal")
			local nodes = array(row.facts)
			assert(#nodes > 0, "content capture has no root")
			local kind = record(row.request).kind
			local rootClass = record(nodes[1]).className
			assert(
				rootClass
					== (if kind == "model" then "Model" elseif kind == "mesh" then "MeshPart" else "KeyframeSequence"),
				"content capture has the wrong root class"
			)
			for index, node in nodes do
				local fields = record(node)
				text(fields.className)
				local needed = required[fields.className :: string]
				if needed then
					requireFields(fields, needed)
				end
				assert(type(fields.name) == "string", "content node requires a name")
				if index == 1 then
					assert(fields.parent == nil, "content root must be unparented")
				else
					assert(integer(fields.parent, 1) < index, "content parent must precede its child")
				end
				for field, item in fields do
					if vectors[field] then
						numbers(item, 3)
					elseif frames[field] ~= nil then
						numbers(item, 12)
					elseif references[field] then
						assert(integer(item, 1) <= #nodes, "content reference is out of range")
					elseif enums[field] then
						text(item)
					elseif scalars[field] then
						local expected = if field == "time" or field == "weight"
							then "number"
							elseif field == "canCollide" or field == "canQuery" or field == "loop" then "boolean"
							else "string"
						assert(type(item) == expected, "invalid content field: " .. field)
						if expected == "number" then
							numbers({ item }, 1)
						end
					else
						assert(
							field == "name" or field == "className" or field == "parent",
							"unknown content field: " .. field
						)
					end
				end
			end
		else
			assert(row.facts == nil, "refused content capture has facts")
			text(row.refusal)
		end
	end
	requests(inputs)
	return (capture :: unknown) :: Capture
end

local function attach(environment: Environment.Environment, value: unknown, library: Datatypes.Library?)
	local capture = validate(value)
	local types = library or Datatypes
	local function load(kind: string, id: number): Environment.Instance
		local found: Row? = nil
		for _, row in capture.rows do
			if row.request.kind == kind and (row.request.version or row.request.id) == id then
				assert(found == nil, "ambiguous content capture ID")
				found = row
			end
		end
		assert(found ~= nil, "unsupported_content: no captured " .. kind .. " ID " .. tostring(id))
		assert(found.ok, "content refused: " .. tostring(found.refusal))
		local nodes = assert(found.facts)
		local objects: { Environment.Instance } = {}
		local ok, failure = pcall(function()
			for index, node in nodes do
				local object = environment.createEngineInstance(node.className :: string)
				objects[index] = object
				for class, fields in required do
					if object:IsA(class) then
						requireFields(node, fields)
					end
				end
				object.Name = node.name
				for field, item in node do
					local property = vectors[field]
					if field == "size" and object:IsA "Model" then
						continue
					end
					if property then
						local components = numbers(item, 3)
						environment.poke(object, property, types.Vector3.new(table.unpack(components)))
					elseif frames[field] then
						environment.poke(
							object,
							frames[field] :: string,
							types.CFrame.new(table.unpack(numbers(item, 12)))
						)
					elseif scalars[field] then
						local target = if field == "textureId" and node.className == "SpecialMesh"
							then "TextureId"
							else scalars[field] :: string
						if maps[field] then
							environment.poke(
								object,
								maps[field],
								if item == "" then types.Content.none else types.Content.fromUri(item :: string)
							)
						else
							environment.poke(object, target, item)
						end
					elseif enums[field] then
						local spec = enums[field] :: { string }
						environment.poke(object, spec[1], types.Enum[spec[2]][item :: string])
					end
				end
				if object:IsA "BaseScript" then
					environment.poke(object, "Disabled", true)
				end
			end
			for index, node in nodes do
				local object = objects[index]
				for field, property in references do
					if node[field] then
						environment.poke(object, property, objects[node[field] :: number])
					end
				end
				if node.parent then
					object.Parent = objects[node.parent :: number]
				end
			end
		end)
		if not ok then
			for _, object in objects do
				if environment.isAlive(object) then
					object:Destroy()
				end
			end
			error(failure, 0)
		end
		return objects[1]
	end
	environment.fake("InsertService.LoadAssetVersion", function(service: Environment.Instance, id: number)
		local model = load("model", integer(id, 1))
		local ok, failure = pcall(function()
			model.Parent = service
		end)
		if not ok then
			model:Destroy()
			error(failure, 0)
		end
		return model
	end)
	environment.fake(
		"AssetService.CreateMeshPartAsync",
		function(_service: Environment.Instance, content: Datatypes.ContentValue, options: unknown)
			assert(
				options == nil or (type(options) == "table" and next(options :: { [string]: unknown }) == nil),
				"unsupported_content: mesh options change captured geometry"
			)
			local uri = content.Uri
			assert(type(uri) == "string", "mesh capture requires URI content")
			return load("mesh", integer(tonumber(string.match(uri, "^rbxassetid://(%d+)$")), 1))
		end
	)
	environment.fake(
		"KeyframeSequenceProvider.GetKeyframeSequenceAsync",
		function(_service: Environment.Instance, uri: string)
			return load("animation", integer(tonumber(string.match(uri, "^rbxassetid://(%d+)$")), 1))
		end
	)
	for _, spec in
		{
			{ "KeyframeSequence.GetKeyframes", "Keyframe" },
			{ "Keyframe.GetPoses", "Pose" },
			{ "Pose.GetSubPoses", "Pose" },
		}
	do
		environment.fake(spec[1], function(object: Environment.Instance)
			local children = {}
			for _, child in object:GetChildren() do
				if child:IsA(spec[2]) then
					table.insert(children, child)
				end
			end
			return children
		end)
	end
end

return { requests = requests, validate = validate, attach = attach }
