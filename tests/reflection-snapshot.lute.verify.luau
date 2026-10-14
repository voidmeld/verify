--!strict

local Datatypes = require "../src/roblox/datatypes"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Verify = require "../src/core"

local FIXTURE = "tests/fixtures/reflection-snapshot.json"
local STUDIO = "tests/fixtures/studio-reflection.json"

local function accepts(body: () -> unknown): boolean
	return (pcall(body))
end

return function(suite: Verify.Harness)
	suite:suite("reflection snapshot loaded under Lute", function()
		suite:case("builds the bridge from the exported file", function(check)
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

		suite:case("gives instances the events the snapshot records for their classes", function(check)
			local bridge = Roblox.reflectionSnapshot.bridge {
				schemaVersion = 2,
				classes = {
					Base = { tags = {}, properties = {}, defaults = {}, events = { "Pinged" } },
					Leaf = { superclass = "Base", tags = {}, properties = {}, defaults = {}, events = { "Popped" } },
				},
			}
			local leaf = bridge.environment.createInstance "Leaf"
			local fired: { string } = {}
			local pinged = leaf.Pinged :: { Connect: (unknown, () -> ()) -> unknown }
			local popped = leaf.Popped :: { Connect: (unknown, () -> ()) -> unknown }
			pinged:Connect(function()
				table.insert(fired, "Pinged")
			end)
			popped:Connect(function()
				table.insert(fired, "Popped")
			end)
			bridge.environment.fire(leaf, "Pinged")
			bridge.environment.fire(leaf, "Popped")
			check:expect(fired):toEqual { "Pinged", "Popped" }
		end)

		suite:case("decodes non-finite numbers carried as tagged strings", function(check)
			local database = Roblox.reflectionSnapshot.database {
				schemaVersion = 2,
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
				schemaVersion = 2,
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

		suite:case("accepts nil or a CFrame for an optional CFrame property", function(check)
			local bridge = Roblox.reflectionSnapshot.bridge {
				schemaVersion = 2,
				classes = {
					Instance = { tags = { "NotCreatable" }, properties = {}, defaults = {} },
					Pivot = {
						superclass = "Instance",
						tags = {},
						properties = {
							Offset = { datatype = "OptionalCFrame", scriptability = "ReadWrite", tags = {} },
						},
						defaults = {},
					},
				},
			}
			local object = bridge.environment.createInstance "Pivot"
			local verdicts = {
				accepts(function(): unknown
					object.Offset = Datatypes.CFrame.new(1, 2, 3)
					return nil
				end),
				accepts(function(): unknown
					object.Offset = nil
					return nil
				end),
				accepts(function(): unknown
					object.Offset = Datatypes.Vector3.new()
					return nil
				end),
			}
			check:expect(verdicts):toEqual { true, true, false }
		end)

		suite:case("refuses a snapshot of another schema or with a malformed class", function(check)
			check
				:expect(accepts(function(): unknown
					return Roblox.reflectionSnapshot.database { schemaVersion = 1, classes = {} }
				end))
				:toBe(false)
			check
				:expect(accepts(function(): unknown
					return Roblox.reflectionSnapshot.database {
						schemaVersion = 2,
						classes = { Bad = (5 :: unknown) :: Roblox.ReflectionSnapshotClass },
					}
				end))
				:toBe(false)
		end)
	end)

	suite:suite("reflection snapshot exported from Studio", function()
		suite:case("creates GUI instances with the defaults that Instance.new gave in Studio", function(check)
			local snapshot = Lute.fixture.load(STUDIO)
			local types = Roblox.reflectionSnapshot.library(snapshot)
			local env = Lute.fixture.bridge(snapshot).environment
			local label = env.createInstance "TextLabel"
			check:expect(label.Text):toBe "Label"
			check:expect(label.TextXAlignment):toBe(types.Enum.TextXAlignment.Center)
			check:expect(label.FontFace):toBe(types.Font.fromEnum(types.Enum.Font.Legacy))
			check:expect((label.TextColor3 :: Roblox.DatatypeColor3):ToHex()):toBe "1b2a35"
			check:expect(label.Size):toBe(types.UDim2.new())
			check:expect(label.Visible):toBe(true)
			check:expect(label:IsA "GuiObject"):toBe(true)
			local corner = env.createInstance "UICorner"
			check:expect(corner.CornerRadius):toBe(types.UDim.new(0, 8))
			local list = env.createInstance "UIListLayout"
			check:expect(list.SortOrder):toBe(types.Enum.SortOrder.Name)
			local part = env.createInstance "Part"
			check:expect(part.BrickColor):toBe(types.BrickColor.new "Medium stone grey")
			check:expect(part.Material):toBe(types.Enum.Material.Plastic)
			check:expect(part.Size):toBe(types.Vector3.new(4, 1.2, 2))
			check:expect(part.CFrame):toBe(types.CFrame.new())
		end)

		suite:case("validates writes with the bound datatypes and enums", function(check)
			local snapshot = Lute.fixture.load(STUDIO)
			local types = Roblox.reflectionSnapshot.library(snapshot)
			local env = Lute.fixture.bridge(snapshot).environment
			local label = env.createInstance "TextLabel"
			label.Size = types.UDim2.fromOffset(10, 20) + types.UDim2.fromScale(0.5, 0)
			check:expect(tostring(label.Size)):toBe "{0.5, 10}, {0, 20}"
			label.TextXAlignment = types.Enum.TextXAlignment.Left
			label.TextColor3 = types.Color3.fromHSV(0.5, 0.5, 0.5)
			label.FontFace = types.Font.fromName("GothamSSm", types.Enum.FontWeight.Bold)
			check:expect((label.FontFace :: Roblox.DatatypeFont).Bold):toBe(true)
			local verdicts = {
				accepts(function(): unknown
					label.TextXAlignment = types.Enum.FontWeight.Bold
					return nil
				end),
				accepts(function(): unknown
					label.Text = 5
					return nil
				end),
				accepts(function(): unknown
					label.AbsoluteSize = types.Vector2.zero
					return nil
				end),
				accepts(function(): unknown
					label.Size = types.Vector2.zero
					return nil
				end),
				accepts(function(): unknown
					label.Rotation = 45
					return nil
				end),
			}
			check:expect(verdicts):toEqual { false, false, false, false, true }
		end)

		suite:case("keeps engine class tags and refuses enums the snapshot lacks", function(check)
			local snapshot = Lute.fixture.load(STUDIO)
			local types = Roblox.reflectionSnapshot.library(snapshot)
			local bridge = Lute.fixture.bridge(snapshot)
			check:expect(snapshot.classes.GuiService.tags):toEqual { "NotCreatable", "Service" }
			check:expect(snapshot.classes.GuiObject.tags):toEqual { "NotCreatable" }
			check
				:expect(accepts(function(): unknown
					return bridge.environment.createInstance "GuiObject"
				end))
				:toBe(false)
			check
				:expect(accepts(function(): unknown
					return ((types.Enum :: unknown) :: { [string]: unknown }).KeyCode
				end))
				:toBe(false)
			check:expect(type(snapshot.engineVersion)):toBe "string"
		end)

		suite:case("gives the engine seam constructors that produce the bound datatypes", function(check)
			local snapshot = Lute.fixture.load(STUDIO)
			local types = Roblox.reflectionSnapshot.library(snapshot)
			local engine = Lute.fixture.bridge(snapshot).engine
			local datatypes = engine.datatypes
			local vector = (datatypes.Vector2 :: (number, number) -> Roblox.EnvironmentEngineVector2)(1, 2)
			check:expect(engine.typeName(vector)):toBe "Vector2"
			check:expect(vector):toBe(types.Vector2.new(1, 2))
			type MakeFrame = (Roblox.EnvironmentEngineVector3, { number }) -> Roblox.EnvironmentEngineCFrame
			local position = (types.Vector3.new(1, 2, 3) :: unknown) :: Roblox.EnvironmentEngineVector3
			local frame = (datatypes.CFrame :: MakeFrame)(position, { 1, 0, 0, 0, 1, 0, 0, 0, 1 })
			check:expect(engine.typeName(frame)):toBe "CFrame"
			local readCFrame =
				engine.readCFrame :: (Roblox.EnvironmentEngineCFrame) -> (number, number, number, { number })
			local x, y, z = readCFrame(frame)
			check:expect({ x, y, z }):toEqual { 1, 2, 3 }
		end)
	end)
end
