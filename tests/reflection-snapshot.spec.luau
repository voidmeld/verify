--!strict

local Datatypes = require "../src/roblox/datatypes"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Verify = require "../src/core"

local FIXTURE = "tests/fixtures/reflection-snapshot.json"

local function accepts(body: () -> unknown): boolean
	return (pcall(body))
end

return function(suite: Verify.Harness)
	suite:suite("reflection snapshot loaded under Lute", function()
		suite:case("builds the bridge from the exported file with no Lune at test time", function(check)
			local bridge = Lute.fixture.bridge(FIXTURE)
			local env = bridge.environment
			local part = env.createInstance "Part"
			check:expect(part.Anchored):toBe(false)
			check:expect((part.Size :: Datatypes.Vector3Value).X):toBe(4)
			check:expect(bridge.hasClass "TextLabel"):toBe(true)
			check:expect(bridge.hasClass "Camera"):toBe(false)
		end)

		suite:case("accepts and refuses writes like the real database did when it was exported", function(check)
			local bridge = Lute.fixture.bridge(FIXTURE)
			local part = bridge.environment.createInstance "Part"
			local label = bridge.environment.createInstance "TextLabel"
			local vector = Datatypes.Vector3.new(1, 2, 3)
			local verdicts = {
				accepts(function(): unknown
					part.Size = vector
					return nil
				end),
				accepts(function(): unknown
					part.Size = "invalid"
					return nil
				end),
				accepts(function(): unknown
					part.Material = Datatypes.Enum.Material.Plastic
					return nil
				end),
				accepts(function(): unknown
					part.Material = Datatypes.Enum.KeyCode.A
					return nil
				end),
				accepts(function(): unknown
					part.Anchored = 42
					return nil
				end),
				accepts(function(): unknown
					part.Unknown = true
					return nil
				end),
				accepts(function(): unknown
					label.AbsoluteSize = vector
					return nil
				end),
			}
			check:expect(verdicts):toEqual { true, false, true, false, false, false, false }
		end)

		suite:case("decodes the tagged default values into Verify datatypes", function(check)
			local database = Roblox.reflectionSnapshot.database(Lute.fixture.load(FIXTURE))
			local label = database:GetClass "TextLabel"
			check:expect(label ~= nil):toBe(true)
			local defaults = (label :: Roblox.ReflectionClass).DefaultProperties
			check:expect(Datatypes.typeName(defaults.TextColor3)):toBe "Color3"
			check:expect(Datatypes.typeName(defaults.TextXAlignment)):toBe "EnumItem"
			check:expect(Datatypes.enumType(defaults.TextXAlignment)):toBe "TextXAlignment"
		end)

		suite:case("reads a property the snapshot stores no default for as unset", function(check)
			local env = Lute.fixture.bridge(FIXTURE).environment
			check:expect(env.createInstance("Model").PrimaryPart):toBe(nil)
			check:expect(env.createInstance("Part").Anchored):toBe(false)
		end)

		suite:case("decodes non-finite numbers carried as tagged strings", function(check)
			local database = Roblox.reflectionSnapshot.database {
				schemaVersion = 1,
				classes = {
					Probe = {
						superclass = nil,
						tags = {},
						properties = {},
						defaults = {
							Far = { ["$"] = "number", v = "inf" },
							Near = { ["$"] = "number", v = "-inf" },
							Unset = { ["$"] = "number", v = "nan" },
							Raw = { ["$"] = "bytes", v = "ff41" },
						},
					},
				},
			}
			local defaults = (database:GetClass "Probe" :: Roblox.ReflectionClass).DefaultProperties
			check:expect(defaults.Far):toBe(math.huge)
			check:expect(defaults.Near):toBe(-math.huge)
			check:expect(defaults.Unset ~= defaults.Unset):toBe(true)
			check:expect(defaults.Raw):toBe "\255A"
		end)

		suite:case("lets a test define a class the snapshot never held and accepts content strings", function(check)
			local bridge = Lute.fixture.bridge(FIXTURE)
			bridge.environment.defineClass("RecoveryRoot", { super = "Instance", properties = { Marker = false } })
			local root = bridge.environment.createInstance "RecoveryRoot"
			root.Marker = true
			check:expect(root.Marker):toBe(true)
			local sound = Roblox.reflectionSnapshot.bridge {
				schemaVersion = 1,
				classes = {
					Instance = { tags = { "NotCreatable" }, properties = {}, defaults = {} },
					Sound = {
						superclass = "Instance",
						tags = {},
						properties = { SoundId = { datatype = "ContentId", scriptability = "ReadWrite", tags = {} } },
						defaults = {},
					},
				},
			}
			local instance = sound.environment.createInstance "Sound"
			instance.SoundId = "rbxassetid://1"
			check:expect(instance.SoundId):toBe "rbxassetid://1"
			check
				:expect(accepts(function(): unknown
					instance.SoundId = 5
					return nil
				end))
				:toBe(false)
		end)

		suite:case(
			"treats a class the test redefines as a declared double and leaves the others validated",
			function(check)
				local bridge = Lute.fixture.bridge(FIXTURE)
				local env = bridge.environment
				local before = env.createInstance "Part"
				check
					:expect(accepts(function(): unknown
						before.Anchored = 42
						return nil
					end))
					:toBe(false)
				env.defineClass(
					"Folder",
					{ super = "Instance", properties = { LocalPlayer = false } },
					{ replace = true }
				)
				local folder = env.createInstance "Folder"
				folder.LocalPlayer = { fake = true }
				check:expect(typeof(folder.LocalPlayer)):toBe "table"
				local part = env.createInstance "Part"
				check
					:expect(accepts(function(): unknown
						part.Anchored = 42
						return nil
					end))
					:toBe(false)
			end
		)

		suite:case("refuses a snapshot of another schema or with a malformed class", function(check)
			check
				:expect(accepts(function(): unknown
					return Roblox.reflectionSnapshot.database { schemaVersion = 2, classes = {} }
				end))
				:toBe(false)
			check
				:expect(accepts(function(): unknown
					return Roblox.reflectionSnapshot.database {
						schemaVersion = 1,
						classes = { Bad = (5 :: unknown) :: Roblox.ReflectionSnapshotClass },
					}
				end))
				:toBe(false)
		end)
	end)
end
