--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local Facts = require "../src/roblox/content-facts"
local Environment = require "../src/roblox/environment"
local Types = require "../src/roblox/datatypes"
local Names = require "../src/roblox/datatypes/names"
local fs = require "@std/fs"
local Wire = require "../src/lute/wire"
local fixture = Facts.validate(Wire.parse(fs.readFileToString "tests/fixtures/content-facts.json"))

local function call(environment: Environment.Environment, object: unknown, name: string, ...: unknown): ...unknown
	local instance = Environment.assertInstance(object)
	return environment.method(instance, name)(instance, ...)
end

local function child(object: unknown, name: string): Environment.Instance
	return assert(Environment.assertInstance(object):FindFirstChild(name))
end

local function array(value: unknown): { unknown }
	assert(type(value) == "table")
	local result: { unknown } = {}
	for _, item in value do
		table.insert(result, item)
	end
	return result
end

local function copy(): Facts.Capture
	return Facts.validate(Wire.parse(Wire.encode(fixture)))
end

it("content records reconstruct independent hierarchies references and native fields", function()
	local engine = Lute.fixture.bridge(nil, { content = { facts = copy() } }).placeEngine()
	local service = engine.service "InsertService"
	local load = engine.environment.method(service, "LoadAssetVersion")
	local first, second = load(service, 42), load(service, 42)
	local body = child(first, "Body")
	expect(Environment.read(body, "MeshSize")):toEqual(Types.Vector3.new(1, 2, 3))
	expect(Environment.read(body, "HasSkinnedMesh")):toBe(true)
	expect(Environment.read(child(second, "Body"), "HasSkinnedMesh")):toBe(true)
	expect(Environment.read(first, "PrimaryPart")):toBe(body)
	expect(Environment.read(child(body, "Motor"), "Part0")):toBe(body)
	expect(Environment.read(child(body, "Constraint"), "Attachment1")):toBe(child(body, "Bone"))
	expect(Names.fields(Environment.read(child(body, "Surface"), "ColorMapContent")).Uri):toBe "rbxassetid://50"
	expect(Environment.read(child(first, "NeverRun"), "Disabled")):toBe(true)
	body:Destroy()
	expect(Environment.read(child(second, "Body"), "Size")):toEqual(Types.Vector3.new(2, 4, 6))
	local count = engine.environment.liveObjects()
	local ok, refusal = pcall(load, service, 45)
	expect(ok):toBe(false)
	expect(string.find(tostring(refusal), "fixture load refused", 1, true) ~= nil):toBe(true)
	expect(pcall(load, service, 99)):toBe(false)
	expect(engine.environment.liveObjects()):toBe(count)
	engine.environment.failNext "setParent"
	expect(pcall(load, service, 42)):toBe(false)
	expect(engine.environment.liveObjects()):toBe(count)
end)

it("a mesh record without a skinned-mesh fact leaves HasSkinnedMesh false", function()
	local engine = Lute.fixture.bridge(nil, { content = { facts = copy() } }).placeEngine()
	local service = engine.service "AssetService"
	local create = engine.environment.method(service, "CreateMeshPartAsync")
	local mesh = create(service, Types.Content.fromAssetId(43), nil)
	expect(Environment.read(mesh, "HasSkinnedMesh")):toBe(false)
end)

it("mesh and animation records answer only captured IDs and supported options", function()
	local engine = Lute.fixture.bridge(nil, { content = { facts = copy() } }).placeEngine()
	local service = engine.service "AssetService"
	local mesh = engine.environment.method(service, "CreateMeshPartAsync")
	local part = mesh(service, Types.Content.fromAssetId(43), nil)
	expect(Environment.read(part, "Size")):toEqual(Types.Vector3.new(2, 4, 6))
	expect(Environment.read(part, "MeshSize")):toEqual(Types.Vector3.new(1, 2, 3))
	expect(pcall(mesh, service, Types.Content.fromAssetId(99), nil)):toBe(false)
	expect(pcall(mesh, service, Types.Content.fromAssetId(43), { RenderFidelity = "Automatic" })):toBe(false)
	local provider = engine.service "KeyframeSequenceProvider"
	local load = engine.environment.method(provider, "GetKeyframeSequenceAsync")
	local sequence = load(provider, "rbxassetid://44")
	local frames = array(call(engine.environment, sequence, "GetKeyframes"))
	expect(Environment.read(sequence, "Loop")):toBe(true)
	expect(Environment.read(frames[1], "Time")):toBe(0.5)
	local poses = array(call(engine.environment, frames[1], "GetPoses"))
	expect(Environment.read(poses[1], "Weight")):toBe(0.75)
	expect(tostring(Environment.read(poses[1], "EasingStyle"))):toBe "Enum.PoseEasingStyle.Linear"
	expect(#array(call(engine.environment, poses[1], "GetSubPoses"))):toBe(1)
	expect(pcall(load, provider, "rbxassetid://99")):toBe(false)
end)

it("content validation rejects malformed graphs results and nonfinite measurements", function()
	local malformed = copy()
	assert(malformed.rows[1].facts)[2].parent = 2
	expect(pcall(Facts.validate, malformed)):toBe(false)
	malformed = copy()
	assert(malformed.rows[1].facts)[1].primaryPart = 99
	expect(pcall(Facts.validate, malformed)):toBe(false)
	malformed = copy()
	assert(malformed.rows[1].facts)[2].meshSize = { 1, math.huge, 3 }
	expect(pcall(Facts.validate, malformed)):toBe(false)
	malformed = copy()
	malformed.rows[4].facts = {}
	expect(pcall(Facts.validate, malformed)):toBe(false)
	malformed = copy()
	assert(malformed.rows[1].facts)[2].meshSize = nil
	expect(pcall(Facts.validate, malformed)):toBe(false)
	expect(pcall(Facts.requests, { { kind = "model", key = "latest", id = 42 } })):toBe(false)
	expect(pcall(Facts.requests, { { kind = "mesh", key = "bad", id = -1 } })):toBe(false)
	expect(pcall(Facts.requests, { fixture.rows[1].request, fixture.rows[1].request })):toBe(false)
end)

it("failed content reconstruction releases partial objects", function()
	local broken = copy()
	assert(broken.rows[1].facts)[3].className = "UnknownCapturedClass"
	local engine = Lute.fixture.bridge(nil, { content = { facts = broken } }).placeEngine()
	local service = engine.service "InsertService"
	local count = engine.environment.liveObjects()
	expect(pcall(engine.environment.method(service, "LoadAssetVersion"), service, 42)):toBe(false)
	expect(engine.environment.liveObjects()):toBe(count)
end)

return nil
