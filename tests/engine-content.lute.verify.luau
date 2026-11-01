--!strict
--!nolint LocalUnused

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Environment = require "../src/roblox/environment"
local Datatypes = require "../src/roblox/datatypes"
local Roblox = require "../src/roblox"

type Instance = Environment.Instance
local function call(environment: Environment.Environment, object: unknown, name: string, ...: unknown): ...unknown
	local instance = Environment.assertInstance(object)
	return environment.method(instance, name)(instance, ...)
end

local function array(value: unknown): { unknown }
	assert(type(value) == "table")
	local result: { unknown } = {}
	for _, item in value do
		table.insert(result, item)
	end
	return result
end

local function children(environment: Environment.Environment, object: unknown): { unknown }
	return array(call(environment, object, "GetChildren"))
end

it("asset versions load independent copies of supplied content under InsertService", function()
	local template: Instance? = nil
	local requested: { number } = {}
	local bridge = Lute.fixture.bridge(nil, {
		content = {
			assetVersion = function(version)
				table.insert(requested, version)
				return if version == 42 then template else nil
			end,
		},
	})
	local engine = bridge.placeEngine()
	local source = engine.newInstance "Model"
	template = source
	source.Name = "Fixture"
	local part = engine.newInstance "Part"
	part.Size = engine.datatypes.Vector3.new(3, 4, 5)
	part.Parent = template
	local service = engine.service "InsertService"
	local load = engine.environment.method(service, "LoadAssetVersion")
	local first = load(service, 42)
	local second = load(service, 42)
	expect(Environment.read(first, "Parent")):toBe(service)
	expect(Environment.read(first, "Name")):toBe "Fixture"
	expect(first == second):toBe(false)
	expect(Environment.read(children(engine.environment, first)[1], "Size")):toEqual(part.Size)
	call(engine.environment, children(engine.environment, first)[1], "Destroy")
	expect(#children(engine.environment, second)):toBe(1)
	expect(#source:GetChildren()):toBe(1)
	expect((pcall(load, service, 99))):toBe(false)
	expect((pcall(load, service, -1))):toBe(false)
	expect((pcall(load, service, math.huge))):toBe(false)
	expect((pcall(load, service, 1.5))):toBe(false)
	expect(requested):toEqual { 42, 42, 99 }
	expect(#service:GetChildren()):toBe(2)
	local alive = engine.environment.liveObjects()
	engine.environment.failNext "setParent"
	expect((pcall(load, service, 42))):toBe(false)
	expect(engine.environment.liveObjects()):toBe(alive)
	expect(#service:GetChildren()):toBe(2)
end)
it("localization tables store entries and format keys through a translator", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local localization = engine.newInstance "LocalizationTable"
	type Entries = { { Key: string, Source: string, Values: { [string]: string } } }
	local entries: Entries = {
		{ Key = "greeting", Source = "Hello {name}", Values = { es = "Hola {name}" } },
		{ Key = "count", Source = "{1} games", Values = {} },
	}
	local setEntries = engine.environment.method(localization, "SetEntries")
	setEntries(localization, entries)
	entries[1].Source = "changed after storing"
	local stored = array(call(engine.environment, localization, "GetEntries"))
	expect(Environment.read(stored[1], "Source")):toBe "Hello {name}"
	local spanish = call(engine.environment, localization, "GetTranslator", "es")
	local translate = Lute.chunk.load(
		"local name = ... return translator[name](translator, select(2, ...))",
		{ environment = { translator = spanish } }
	)
	local named: { [string | number]: unknown } = { name = "Ada" }
	local positional: { [string | number]: unknown } = { 3 }
	expect(translate("FormatByKey", "greeting", named)):toBe "Hola Ada"
	expect(translate("FormatByKey", "count", positional)):toBe "3 games"
	expect(translate("Translate", nil, "Hello {name}")):toBe "Hola {name}"
	expect(pcall(translate, "FormatByKey", "missing")):toBe(false)
end)
it("asset loading refuses absent providers and invalid content without inventing geometry", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local service = engine.service "InsertService"
	local load = engine.environment.method(service, "LoadAssetVersion")
	local ok, message = pcall(load, service, 42)
	expect(ok):toBe(false)
	expect(string.find(tostring(message), "requires an assetVersion provider", 1, true) ~= nil):toBe(true)
	local supplied = engine.newInstance "Model"
	local bridge = Lute.fixture.bridge(nil, { content = {
		assetVersion = function()
			return supplied
		end,
	} })
	local other = bridge.placeEngine()
	local otherService = other.service "InsertService"
	local otherLoad = other.environment.method(otherService, "LoadAssetVersion")
	expect((pcall(otherLoad, otherService, 42))):toBe(false)
	supplied = other.newInstance "Folder"
	expect((pcall(otherLoad, otherService, 42))):toBe(false)
	supplied = other.newInstance "Model"
	supplied.Archivable = false
	expect((pcall(otherLoad, otherService, 42))):toBe(false)
	supplied:Destroy()
	expect((pcall(otherLoad, otherService, 42))):toBe(false)
	expect(#otherService:GetChildren()):toBe(0)
end)
it("terrain colors round trip overrides and read supplied material facts", function()
	local calls = 0
	local bridge = Lute.fixture.bridge(nil, {
		content = {
			terrainMaterialColor = function()
				calls += 1
				return Datatypes.Color3.new(0.2, 0.3, 0.4)
			end,
		},
	})
	local engine = bridge.placeEngine()
	local terrain = engine.newInstance("Terrain", true)
	local get = engine.environment.method(terrain, "GetMaterialColor")
	local set = engine.environment.method(terrain, "SetMaterialColor")
	local grass = engine.datatypes.Enum.Material.Grass
	local tint = engine.datatypes.Color3.new(0.8, 0.7, 0.6)
	expect(get(terrain, grass)):toEqual(engine.datatypes.Color3.new(0.2, 0.3, 0.4))
	set(terrain, grass, tint)
	expect(get(terrain, grass)):toEqual(tint)
	expect(calls):toBe(1)
	local invalidMaterials: { unknown } = {
		engine.datatypes.Enum.Material.Air,
		engine.datatypes.Enum.Material.Water,
		engine.datatypes.Enum.Font.Code,
		"Grass",
	}
	for _, invalid in invalidMaterials do
		expect((pcall(set, terrain, invalid, tint))):toBe(false)
		expect((pcall(get, terrain, invalid))):toBe(false)
	end
	expect((pcall(set, terrain, grass, "red"))):toBe(false)
	expect(get(terrain, grass)):toEqual(tint)
	local missingEngine = Lute.fixture.bridge().placeEngine()
	local missing = missingEngine.newInstance("Terrain", true)
	local readMissing = missingEngine.environment.method(missing, "GetMaterialColor")
	expect((pcall(readMissing, missing, grass))):toBe(false)
end)
it("log history records real diagnostics with levels clock ordering copies and bounded retention", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local log = engine.service "LogService"
	local history = engine.environment.method(log, "GetLogHistory")
	local clear = engine.environment.method(log, "ClearOutput")
	expect(history(log)):toEqual {}
	local received: { { message: string, kind: unknown } } = {}
	local signal = engine.environment.event(log, "MessageOut")
	local connection = signal:Connect(function(message: unknown, kind: unknown)
		assert(type(message) == "string")
		table.insert(received, { message = message, kind = kind })
	end)
	local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
	})
	local output = Lute.chunk.load("print(...)", { environment = runtime.globals })
	local warn = Lute.chunk.load("warn(...)", { environment = runtime.globals })
	output "hello"
	engine.environment.step(0.5)
	warn "warning"
	engine.record("error", "failure", "fixture")
	local rawEntries = history(log)
	local entries = array(rawEntries)
	expect(Environment.read(entries[1], "messageType")):toBe(engine.datatypes.Enum.MessageType.MessageOutput)
	expect(Environment.read(entries[2], "messageType")):toBe(engine.datatypes.Enum.MessageType.MessageWarning)
	expect(Environment.read(entries[3], "messageType")):toBe(engine.datatypes.Enum.MessageType.MessageError)
	expect(Environment.read(entries[2], "timestamp")):toBe(0.5)
	expect(#received):toBe(3)
	local entry = entries[1]
	assert(type(entry) == "table")
	table.clear(entry)
	assert(type(rawEntries) == "table")
	table.clear(rawEntries)
	expect(Environment.read(array(history(log))[1], "message")):toBe "hello"
	for index = 1, 513 do
		engine.record("print", tostring(index), "fixture")
	end
	expect(#array(history(log))):toBe(512)
	expect(Environment.read(array(history(log))[1], "message")):toBe "2"
	clear(log)
	expect(history(log)):toEqual {}
	expect(#engine.diagnostics):toBe(516)
	connection:Disconnect()
end)
it("incoming chat callbacks are write-only replaceable clearable and callable by the host", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local chat = engine.service "TextChatService"
	expect((pcall(function()
		return chat.OnIncomingMessage
	end))):toBe(false)
	local decorate = function(message: string): string
		return "decorated " .. message
	end
	chat.OnIncomingMessage = decorate
	local callback = engine.environment.propertyOf(chat, "OnIncomingMessage")
	expect(Lute.chunk.load("return callback(...)", { environment = { callback = callback } }) "message"):toBe "decorated message"
	chat.OnIncomingMessage = function() end
	expect(engine.environment.propertyOf(chat, "OnIncomingMessage") == decorate):toBe(false)
	chat.OnIncomingMessage = nil
	expect(engine.environment.propertyOf(chat, "OnIncomingMessage")):toBe(nil)
end)

return nil
