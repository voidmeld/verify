--!strict

local Test = require "./harness"
local it, expect = Test.it, Test.expect
local Lute = require "../src/lute"
local Facts = require "../src/roblox/content-facts"
local Environment = require "../src/roblox/environment-types"
local Types = require "../src/roblox/datatypes"
local fs = require "@std/fs"
local Wire = require "../src/lute/wire"
local fixture = Facts.validate(Wire.parse(fs.readFileToString "tests/fixtures/content-facts.json"))

type Instance = Environment.Instance
type Load = (Instance, number) -> Instance

local function copy(): Facts.Capture
	return Facts.validate(Wire.parse(Wire.encode(fixture)))
end

it("content records reconstruct independent hierarchies references and native fields", function()
	local engine = Lute.fixture.bridge(nil, { content = { facts = copy() } }).placeEngine()
	local service = engine.service "InsertService"
	local load = service.LoadAssetVersion :: Load
	local first, second = load(service, 42), load(service, 42)
	local body = assert(first:FindFirstChild "Body")
	expect(body.MeshSize):toEqual(Types.Vector3.new(1, 2, 3))
	expect(first.PrimaryPart):toBe(body)
	expect(assert(body:FindFirstChild "Motor").Part0):toBe(body)
	expect(assert(body:FindFirstChild "Constraint").Attachment1):toBe(body:FindFirstChild "Bone")
	expect((assert(body:FindFirstChild "Surface").ColorMapContent :: Types.ContentValue).Uri):toBe "rbxassetid://50"
	expect(assert(first:FindFirstChild "NeverRun").Disabled):toBe(true)
	body:Destroy()
	expect(assert(second:FindFirstChild "Body").Size):toEqual(Types.Vector3.new(2, 4, 6))
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

it("mesh and animation records answer only captured IDs and supported options", function()
	local engine = Lute.fixture.bridge(nil, { content = { facts = copy() } }).placeEngine()
	local service = engine.service "AssetService"
	local mesh = service.CreateMeshPartAsync :: (Instance, Types.ContentValue, unknown) -> Instance
	local part = mesh(service, Types.Content.fromAssetId(43), nil)
	expect(part.Size):toEqual(Types.Vector3.new(2, 4, 6))
	expect(part.MeshSize):toEqual(Types.Vector3.new(1, 2, 3))
	expect(pcall(mesh, service, Types.Content.fromAssetId(99), nil)):toBe(false)
	expect(pcall(mesh, service, Types.Content.fromAssetId(43), { RenderFidelity = "Automatic" })):toBe(false)
	local provider = engine.service "KeyframeSequenceProvider"
	local load = provider.GetKeyframeSequenceAsync :: (Instance, string) -> Instance
	local sequence = load(provider, "rbxassetid://44")
	local frames = (sequence.GetKeyframes :: (Instance) -> { Instance })(sequence)
	expect(sequence.Loop):toBe(true)
	expect(frames[1].Time):toBe(0.5)
	local poses = (frames[1].GetPoses :: (Instance) -> { Instance })(frames[1])
	expect(poses[1].Weight):toBe(0.75)
	expect(tostring(poses[1].EasingStyle)):toBe "Enum.PoseEasingStyle.Linear"
	expect(#(poses[1].GetSubPoses :: (Instance) -> { Instance })(poses[1])):toBe(1)
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
	expect(pcall(service.LoadAssetVersion :: Load, service, 42)):toBe(false)
	expect(engine.environment.liveObjects()):toBe(count)
end)

it("native content harness source compiles before a Studio launch", function()
	local luau = require "@lute/luau"
	local source = require "../tools/lib/capture-native-content"
	expect(pcall(luau.compile, source)):toBe(true)
end)

return nil
