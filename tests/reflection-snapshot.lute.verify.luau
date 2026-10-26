--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Datatypes = require "../src/roblox/datatypes"
local path = require "@std/path"
local process = require "@std/process"
local temporary = require "./temporary"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

local FIXTURE = "tests/fixtures/reflection-snapshot.json"
local STUDIO = "tests/fixtures/studio-reflection.json"

local function accepts(body: () -> unknown): boolean
	return (pcall(body))
end

describe("reflection snapshot loaded under Lute", function()
	it("bundled singleton services restore captured capacity and lighting values", function()
		local engine = Lute.fixture.bridge().placeEngine()
		local players = engine.service "Players"
		local lighting = engine.service "Lighting"
		expect(players.MaxPlayers):toBe(12)
		expect(lighting.FogColor):toBe(Datatypes.Color3.new(0.75, 0.75, 0.75))
		expect(lighting.FogEnd):toBe(100000)
		local original = lighting.Ambient
		lighting.Ambient = Datatypes.Color3.new(0, 0, 0)
		lighting.Ambient = original
		expect(lighting.Ambient):toBe(Datatypes.Color3.new(0.5, 0.5, 0.5))
		expect(accepts(function(): unknown
			players.MaxPlayers = 50
			return nil
		end)):toBe(false)
	end)
	it("bundled TextChannel preserves write-only delivery callbacks", function()
		local environment = Lute.fixture.bridge().environment
		local channel = environment.createInstance "TextChannel"
		local deliver = function(): boolean
			return false
		end
		channel.ShouldDeliverCallback = deliver
		expect(environment.propertyOf(channel, "ShouldDeliverCallback") == deliver):toBe(true)
		expect(accepts(function(): unknown
			return channel.ShouldDeliverCallback
		end)):toBe(false)
		expect(accepts(function(): unknown
			channel.ShouldDeliverCallback = true
			return nil
		end)):toBe(true)
		channel.ShouldDeliverCallback = nil
		expect(environment.propertyOf(channel, "ShouldDeliverCallback")):toBe(nil)
	end)
	it("loads the bundled capture from a consumer working directory", function(_, caseContext)
		local directory = temporary(caseContext, "bundled-reflection")
		local source = path.format(path.resolve "tests/programs/bundled-reflection.luau")
		local result = process.run({ tostring(process.execPath()), "run", source }, { cwd = directory })
		assert(result.exitcode == 0, result.stderr)
		expect(result.exitcode):toBe(0)
		expect(result.stdout):toContain "bundled-reflection-ready"
	end)
	it("engine-created InputObject retains metadata validation while script construction stays forbidden", function()
		local snapshot: Roblox.ReflectionSnapshot = {
			schemaVersion = 2,
			engineVersion = "0.742.0.7421053",
			classes = {
				Instance = {
					tags = { "NotCreatable" },
					defaults = {},
					properties = { Name = { datatype = "String", scriptability = "ReadWrite", tags = {} } },
				},
				InputObject = {
					superclass = "Instance",
					tags = { "NotCreatable" },
					defaults = {},
					properties = {
						Position = { datatype = "Vector3", scriptability = "ReadWrite", tags = {} },
					},
				},
			},
		}
		local bridge = Lute.fixture.bridge(snapshot)
		local env = bridge.environment
		local created = 0
		local hook = env.onCreate(function()
			created += 1
		end)
		local object =
			env.createEngineInstance("InputObject", { Name = "OwnedInput", Position = Datatypes.Vector3.new(3, 4, 0) })
		expect(Roblox.isInstance(object)):toBe(true)
		expect(Roblox.typeName(object)):toBe "Instance"
		expect(object:IsA "InputObject"):toBe(true)
		expect(object.Name):toBe "OwnedInput"
		expect(object.Position):toBe(Datatypes.Vector3.new(3, 4, 0))
		expect(env.liveObjects()):toBe(1)
		expect(created):toBe(1)
		expect(pcall(function()
			bridge.engine.new "InputObject"
		end)):toBe(false)
		expect(pcall(function()
			env.createEngineInstance "UnknownInput"
		end)):toBe(false)
		expect(pcall(function()
			object.Position = "invalid"
		end)):toBe(false)
		expect(object.Position):toBe(Datatypes.Vector3.new(3, 4, 0))
		object:Destroy()
		hook:Disconnect()
		expect(env.liveObjects()):toBe(0)
	end)
	it("builds the bridge from the exported file", function()
		local bridge = Lute.fixture.bridge(FIXTURE)
		local env = bridge.environment
		local part = env.createInstance "Part"
		expect(part.Anchored):toBe(false)
		expect((part.Size :: Datatypes.Vector3Value).X):toBe(4)
		expect(bridge.hasClass "TextLabel"):toBe(true)
		expect(bridge.hasClass "Camera"):toBe(false)
		expect(bridge.layout):toBe(nil)
	end)

	it("preserves declared methods and requires an explicit implementation", function()
		local snapshot = Lute.fixture.load(FIXTURE)
		snapshot.classes.Part.methods = { "NativeOnly", "Configured" }
		snapshot.classes.Instance.methods = { "InheritedOnly" }
		local methods: { [string]: unknown } = {
			Configured = function(): number
				return 42
			end,
		}
		local options: Lute.FixtureOptions = {
			classes = { Part = { methods = methods } },
		}
		local bridge = Lute.fixture.bridge(snapshot, options)
		local env = bridge.environment
		local part = env.createInstance "Part"
		expect((part.Configured :: (unknown) -> number)(part)):toBe(42)
		for _, name in { "NativeOnly", "InheritedOnly" } do
			local ok, problem = pcall(function()
				return part[name]
			end)
			expect(ok):toBe(false)
			expect(tostring(problem)):toContain "unsupported_method"
		end
		local close = env.fakeOn(part, "NativeOnly", function(): string
			return "configured"
		end)
		expect((part.NativeOnly :: (unknown) -> string)(part)):toBe "configured"
		close()
		expect(accepts(function()
			return part.NativeOnly
		end)):toBe(false)
		local folder = env.createInstance "Folder"
		local ok, problem = pcall(function()
			return folder.NativeOnly
		end)
		expect(ok):toBe(false)
		expect(tostring(problem)):toContain "not a valid member"
	end)

	it("preserves captured class names when resetting Name", function()
		local snapshot = Lute.fixture.load(FIXTURE)
		snapshot.classes.StringValue = {
			superclass = "Instance",
			tags = {},
			properties = {},
			defaults = { Name = "Value" },
		}
		local bridge = Lute.fixture.bridge(snapshot)
		local object = bridge.environment.createInstance "StringValue"
		expect(object.Name):toBe "Value"
		object.Name = "Renamed"
		object:ResetPropertyToDefault "Name"
		expect(object.Name):toBe "Value"
		expect(object:IsPropertyModified "Name"):toBe(false)
	end)

	it("steps layout over mounted snapshot instances and updates after resize", function()
		local roots: { Roblox.Instance } = {}
		local bridge = Lute.fixture.bridge(FIXTURE, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
			},
		})
		local env = bridge.environment
		local root = env.createInstance("Frame", { Size = Datatypes.UDim2.fromOffset(120, 80) })
		local child = env.createInstance("Frame", {
			Parent = root,
			Size = Datatypes.UDim2.new(0.5, 0, 0, 20),
			Position = Datatypes.UDim2.fromOffset(7, 9),
		})
		table.insert(roots, root)
		local changes = 0
		child:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			changes += 1
		end)
		assert(bridge.layout).step()
		expect(child.AbsoluteSize):toEqual(Datatypes.Vector2.new(60, 20))
		expect(child.AbsolutePosition):toEqual(Datatypes.Vector2.new(7, 9))
		root.Size = Datatypes.UDim2.fromOffset(200, 80)
		assert(bridge.layout).step()
		expect(child.AbsoluteSize):toEqual(Datatypes.Vector2.new(100, 20))
		expect(changes):toBe(2)
		expect(env.now()):toBe(0)
	end)

	it("snapshot layout rejects unsupported text before publishing its mounted ancestors", function()
		local roots: { Roblox.Instance } = {}
		local snapshot = Lute.fixture.load(FIXTURE)
		local types = Roblox.reflectionSnapshot.library(snapshot)
		local bridge = Roblox.reflectionSnapshot.bridge(snapshot, {
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 800, Y = 600 }
				end,
			},
		})
		local env = bridge.environment
		local root = env.createInstance("Frame", { Size = types.UDim2.fromOffset(120, 80) })
		env.createInstance("TextLabel", { Parent = root, AutomaticSize = types.Enum.AutomaticSize.XY })
		table.insert(roots, root)
		local before = root.AbsoluteSize
		local ok, message = pcall(function()
			assert(bridge.layout).step()
		end)
		expect(ok):toBe(false)
		expect(tostring(message)):toContain "AutomaticSize text measurement"
		expect(root.AbsoluteSize):toEqual(before)
	end)

	it("accepts and refuses writes like the real database did when it was exported", function()
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
		expect(verdicts):toEqual { true, false, true, false, false, false, false }
	end)

	it("decodes the tagged default values into Verify datatypes", function()
		local database = Roblox.reflectionSnapshot.database(Lute.fixture.load(FIXTURE))
		local label = database:GetClass "TextLabel"
		expect(label ~= nil):toBe(true)
		local defaults = (assert(label)).DefaultProperties
		expect(Datatypes.typeName(defaults.TextColor3)):toBe "Color3"
		expect(Datatypes.typeName(defaults.TextXAlignment)):toBe "EnumItem"
		expect(Datatypes.enumType(defaults.TextXAlignment)):toBe "TextXAlignment"
	end)

	it("reads a property the snapshot stores no default for as unset", function()
		local env = Lute.fixture.bridge(FIXTURE).environment
		expect(env.createInstance("Model").PrimaryPart):toBe(nil)
		expect(env.createInstance("Part").Anchored):toBe(false)
	end)

	it("gives instances the events the snapshot records for their classes", function()
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
		expect(fired):toEqual { "Pinged", "Popped" }
	end)

	it("decodes non-finite numbers carried as tagged strings", function()
		local database = Roblox.reflectionSnapshot.database {
			schemaVersion = 2,
			classes = {
				Probe = {
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
		local defaults = (assert(database:GetClass "Probe")).DefaultProperties
		expect(defaults.Far):toBe(math.huge)
		expect(defaults.Near):toBe(-math.huge)
		expect(defaults.Unset ~= defaults.Unset):toBe(true)
		expect(defaults.Raw):toBe "\255A"
	end)

	it("lets a test define a class the snapshot never held and accepts content strings", function()
		local bridge = Lute.fixture.bridge(FIXTURE)
		bridge.environment.defineClass("RecoveryRoot", { super = "Instance", properties = { Marker = false } })
		local root = bridge.environment.createInstance "RecoveryRoot"
		root.Marker = true
		expect(root.Marker):toBe(true)
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
		expect(instance.SoundId):toBe "rbxassetid://1"
		expect(accepts(function(): unknown
			instance.SoundId = 5
			return nil
		end)):toBe(false)
	end)

	it("treats a class the test redefines as a declared double and leaves the others validated", function()
		local bridge = Lute.fixture.bridge(FIXTURE)
		local env = bridge.environment
		local before = env.createInstance "Part"
		expect(accepts(function(): unknown
			before.Anchored = 42
			return nil
		end)):toBe(false)
		env.defineClass("Folder", { super = "Instance", properties = { LocalPlayer = false } }, { replace = true })
		local folder = env.createInstance "Folder"
		folder.LocalPlayer = { fake = true }
		expect(typeof(folder.LocalPlayer)):toBe "table"
		local part = env.createInstance "Part"
		expect(accepts(function(): unknown
			part.Anchored = 42
			return nil
		end)):toBe(false)
	end)

	it("accepts unset custom physical properties without loosening other property types", function()
		local bridge = Lute.fixture.bridge()
		local part = bridge.environment.createInstance "Part"
		expect(part.CustomPhysicalProperties):toBe(nil)
		part.CustomPhysicalProperties = nil
		expect(part.CustomPhysicalProperties):toBe(nil)
		expect(accepts(function(): unknown
			part.CustomPhysicalProperties = {}
			return nil
		end)):toBe(false)
		expect(accepts(function(): unknown
			part.Size = nil
			return nil
		end)):toBe(false)
	end)

	it("accepts nil or a CFrame for an optional CFrame property", function()
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
		expect(verdicts):toEqual { true, true, false }
	end)

	it("refuses a snapshot of another schema or with a malformed class", function()
		expect(accepts(function(): unknown
			return Roblox.reflectionSnapshot.database { schemaVersion = 1, classes = {} }
		end)):toBe(false)
		expect(accepts(function(): unknown
			return Roblox.reflectionSnapshot.database {
				schemaVersion = 2,
				classes = { Bad = (5 :: unknown) :: Roblox.ReflectionSnapshotClass },
			}
		end)):toBe(false)
	end)
end)

describe("reflection snapshot exported from Studio", function()
	it("creates GUI instances with the defaults that Instance.new gave in Studio", function()
		local snapshot = Lute.fixture.load(STUDIO)
		local types = Roblox.reflectionSnapshot.library(snapshot)
		local env = Lute.fixture.bridge(snapshot).environment
		local label = env.createInstance "TextLabel"
		expect(label.Text):toBe "Label"
		expect(label.TextXAlignment):toBe(types.Enum.TextXAlignment.Center)
		expect(label.FontFace):toBe(types.Font.fromEnum(types.Enum.Font.Legacy))
		expect((label.TextColor3 :: Roblox.DatatypeColor3):ToHex()):toBe "1b2a35"
		expect(label.Size):toBe(types.UDim2.new())
		expect(label.Visible):toBe(true)
		expect(label:IsA "GuiObject"):toBe(true)
		local corner = env.createInstance "UICorner"
		expect(corner.CornerRadius):toBe(types.UDim.new(0, 8))
		local list = env.createInstance "UIListLayout"
		expect(list.SortOrder):toBe(types.Enum.SortOrder.Name)
		local part = env.createInstance "Part"
		expect(part.BrickColor):toBe(types.BrickColor.new "Medium stone grey")
		expect(part.Material):toBe(types.Enum.Material.Plastic)
		expect(part.Size):toBe(types.Vector3.new(4, 1.2, 2))
		expect(part.CFrame):toBe(types.CFrame.new())
	end)

	it("validates writes with the bound datatypes and enums", function()
		local snapshot = Lute.fixture.load(STUDIO)
		local types = Roblox.reflectionSnapshot.library(snapshot)
		local env = Lute.fixture.bridge(snapshot).environment
		local label = env.createInstance "TextLabel"
		label.Size = types.UDim2.fromOffset(10, 20) + types.UDim2.fromScale(0.5, 0)
		expect(tostring(label.Size)):toBe "{0.5, 10}, {0, 20}"
		label.TextXAlignment = types.Enum.TextXAlignment.Left
		label.TextColor3 = types.Color3.fromHSV(0.5, 0.5, 0.5)
		label.FontFace = types.Font.fromName("GothamSSm", types.Enum.FontWeight.Bold)
		expect((label.FontFace :: Roblox.DatatypeFont).Bold):toBe(true)
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
		expect(verdicts):toEqual { false, false, false, false, true }
	end)

	it("keeps engine class tags and refuses enums the snapshot lacks", function()
		local snapshot = Lute.fixture.load(STUDIO)
		local types = Roblox.reflectionSnapshot.library(snapshot)
		local bridge = Lute.fixture.bridge(snapshot)
		expect(snapshot.classes.GuiService.tags):toEqual { "NotCreatable", "Service" }
		expect(snapshot.classes.GuiObject.tags):toEqual { "NotCreatable" }
		expect(accepts(function(): unknown
			return bridge.environment.createInstance "GuiObject"
		end)):toBe(false)
		expect(accepts(function(): unknown
			return ((types.Enum :: unknown) :: { [string]: unknown }).KeyCode
		end)):toBe(false)
		expect(type(snapshot.engineVersion)):toBe "string"
	end)

	it("gives the engine seam constructors that produce the bound datatypes", function()
		local snapshot = Lute.fixture.load(STUDIO)
		local types = Roblox.reflectionSnapshot.library(snapshot)
		local engine = Lute.fixture.bridge(snapshot).engine
		local datatypes = engine.datatypes
		local vector = (assert(datatypes.Vector2))(1, 2)
		expect(engine.typeName(vector)):toBe "Vector2"
		expect(vector):toBe(types.Vector2.new(1, 2))
		type MakeFrame = (Roblox.EnvironmentEngineVector3, { number }) -> Roblox.EnvironmentEngineCFrame
		local position = (types.Vector3.new(1, 2, 3) :: unknown) :: Roblox.EnvironmentEngineVector3
		local frame = (assert(datatypes.CFrame))(position, { 1, 0, 0, 0, 1, 0, 0, 0, 1 })
		expect(engine.typeName(frame)):toBe "CFrame"
		local readCFrame = assert(engine.readCFrame)
		local x, y, z = readCFrame(frame)
		expect({ x, y, z }):toEqual { 1, 2, 3 }
	end)
end)

return nil
