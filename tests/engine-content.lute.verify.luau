--!strict

local Core = require "../src/core"
local Lute = require "../src/lute"
local Environment = require "../src/roblox/environment"
local LogFakes = require "../src/roblox/log-fakes"
local Datatypes = require "../src/roblox/datatypes"
local Roblox = require "../src/roblox"

type Instance = Environment.Instance
type Load = (Instance, number) -> Instance
type GetColor = (Instance, unknown) -> unknown
type SetColor = (Instance, unknown, unknown) -> ()
type History = (Instance) -> { LogFakes.Entry }

return function(suite: Core.Harness)
	suite:case("asset versions load independent copies of supplied content under InsertService", function(check)
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
		local load = service.LoadAssetVersion :: Load
		local first = load(service, 42)
		local second = load(service, 42)
		check:expect(first.Parent):toBe(service)
		check:expect(first.Name):toBe "Fixture"
		check:expect(first == second):toBe(false)
		check:expect(first:GetChildren()[1].Size):toEqual(part.Size)
		first:GetChildren()[1]:Destroy()
		check:expect(#second:GetChildren()):toBe(1)
		check:expect(#source:GetChildren()):toBe(1)
		check:expect((pcall(load, service, 99))):toBe(false)
		check:expect((pcall(load, service, -1))):toBe(false)
		check:expect((pcall(load, service, math.huge))):toBe(false)
		check:expect((pcall(load, service, 1.5))):toBe(false)
		check:expect(requested):toEqual { 42, 42, 99 }
		check:expect(#service:GetChildren()):toBe(2)
		local alive = engine.environment.liveObjects()
		engine.environment.failNext "setParent"
		check:expect((pcall(load, service, 42))):toBe(false)
		check:expect(engine.environment.liveObjects()):toBe(alive)
		check:expect(#service:GetChildren()):toBe(2)
	end)
	suite:case("asset loading refuses absent providers and invalid content without inventing geometry", function(check)
		local engine = Lute.fixture.bridge().placeEngine()
		local service = engine.service "InsertService"
		local load = service.LoadAssetVersion :: Load
		local ok, message = pcall(load, service, 42)
		check:expect(ok):toBe(false)
		check:expect(string.find(tostring(message), "requires an assetVersion provider", 1, true) ~= nil):toBe(true)
		local supplied = engine.newInstance "Model"
		local bridge =
			Lute.fixture.bridge(nil, { content = {
				assetVersion = function()
					return supplied
				end,
			} })
		local other = bridge.placeEngine()
		local otherService = other.service "InsertService"
		local otherLoad = otherService.LoadAssetVersion :: Load
		check:expect((pcall(otherLoad, otherService, 42))):toBe(false)
		supplied = other.newInstance "Folder"
		check:expect((pcall(otherLoad, otherService, 42))):toBe(false)
		supplied = other.newInstance "Model"
		supplied.Archivable = false
		check:expect((pcall(otherLoad, otherService, 42))):toBe(false)
		supplied:Destroy()
		check:expect((pcall(otherLoad, otherService, 42))):toBe(false)
		check:expect(#otherService:GetChildren()):toBe(0)
	end)
	suite:case("terrain colors round trip overrides and read supplied material facts", function(check)
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
		local get = terrain.GetMaterialColor :: GetColor
		local set = terrain.SetMaterialColor :: SetColor
		local grass = engine.datatypes.Enum.Material.Grass
		local tint = engine.datatypes.Color3.new(0.8, 0.7, 0.6)
		check:expect(get(terrain, grass)):toEqual(engine.datatypes.Color3.new(0.2, 0.3, 0.4))
		set(terrain, grass, tint)
		check:expect(get(terrain, grass)):toEqual(tint)
		check:expect(calls):toBe(1)
		local invalidMaterials: { unknown } = {
			engine.datatypes.Enum.Material.Air,
			engine.datatypes.Enum.Material.Water,
			engine.datatypes.Enum.Font.Code,
			"Grass",
		}
		for _, invalid in invalidMaterials do
			check:expect((pcall(set, terrain, invalid, tint))):toBe(false)
			check:expect((pcall(get, terrain, invalid))):toBe(false)
		end
		check:expect((pcall(set, terrain, grass, "red"))):toBe(false)
		check:expect(get(terrain, grass)):toEqual(tint)
		local missing = Lute.fixture.bridge().placeEngine().newInstance("Terrain", true)
		local readMissing = missing.GetMaterialColor :: GetColor
		check:expect((pcall(readMissing, missing, grass))):toBe(false)
	end)
	suite:case(
		"log history records real diagnostics with levels clock ordering copies and bounded retention",
		function(check)
			local engine = Lute.fixture.bridge().placeEngine()
			local log = engine.service "LogService"
			local history = log.GetLogHistory :: History
			local clear = log.ClearOutput :: (Instance) -> ()
			check:expect(history(log)):toEqual {}
			local received: { { message: string, kind: unknown } } = {}
			local signal = log.MessageOut :: Environment.Signal<string, unknown>
			local connection = signal:Connect(function(message, kind)
				table.insert(received, { message = message, kind = kind })
			end)
			local runtime = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
				aliases = {},
				cache = Roblox.createPlaceCache(Lute.fixture.host),
				host = Lute.fixture.host,
			})
			local output = runtime.globals.print :: (...unknown) -> ()
			local warn = runtime.globals.warn :: (...unknown) -> ()
			output "hello"
			engine.environment.step(0.5)
			warn "warning"
			engine.record("error", "failure", "fixture")
			local entries = history(log)
			check:expect(entries[1].messageType):toBe(engine.datatypes.Enum.MessageType.MessageOutput)
			check:expect(entries[2].messageType):toBe(engine.datatypes.Enum.MessageType.MessageWarning)
			check:expect(entries[3].messageType):toBe(engine.datatypes.Enum.MessageType.MessageError)
			check:expect(entries[2].timestamp):toBe(0.5)
			check:expect(#received):toBe(3)
			entries[1].message = "changed"
			table.clear(entries)
			check:expect(history(log)[1].message):toBe "hello"
			for index = 1, 513 do
				engine.record("print", tostring(index), "fixture")
			end
			check:expect(#history(log)):toBe(512)
			check:expect(history(log)[1].message):toBe "2"
			clear(log)
			check:expect(history(log)):toEqual {}
			check:expect(#engine.diagnostics):toBe(516)
			connection:Disconnect()
		end
	)
	suite:case("incoming chat callbacks are write-only replaceable clearable and callable by the host", function(check)
		local engine = Lute.fixture.bridge().placeEngine()
		local chat = engine.service "TextChatService"
		check
			:expect((pcall(function()
				return chat.OnIncomingMessage
			end)))
			:toBe(false)
		local decorate = function(message: string): string
			return "decorated " .. message
		end
		chat.OnIncomingMessage = decorate
		local callback = engine.environment.propertyOf(chat, "OnIncomingMessage") :: (string) -> string
		check:expect(callback "message"):toBe "decorated message"
		chat.OnIncomingMessage = function() end
		check:expect(engine.environment.propertyOf(chat, "OnIncomingMessage") == decorate):toBe(false)
		chat.OnIncomingMessage = nil
		check:expect(engine.environment.propertyOf(chat, "OnIncomingMessage")):toBe(nil)
	end)
end
