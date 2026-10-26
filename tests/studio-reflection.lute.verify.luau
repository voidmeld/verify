--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local function asString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local fs = require "@std/fs"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

type Fields = { [string]: unknown }
type Member = {
	Name: string,
	Owner: string?,
	Superclass: string?,
	Type: { EngineType: string, ScriptType: string?, EnumType: string? }?,
	Permits: { [string]: unknown },
	Display: { DeprecationMessage: string? },
}

local DIRECTORY = ".lute/tmp/verify-studio-reflection"

local engine = Roblox.datatypes.create {
	enums = {
		TextXAlignment = { { name = "Left", value = 0 }, { name = "Right", value = 1 }, { name = "Center", value = 2 } },
		FontWeight = { { name = "Regular", value = 400 }, { name = "Bold", value = 700 } },
		FontStyle = { { name = "Normal", value = 0 }, { name = "Italic", value = 1 } },
		Font = { { name = "Legacy", value = 0 }, { name = "Unknown", value = 100 } },
		ContentSourceType = { { name = "None", value = 0 }, { name = "Uri", value = 1 } },
		KeyCode = { { name = "Unknown", value = 0 }, { name = "A", value = 97 } },
		Material = { { name = "Plastic", value = 256 } },
		SecurityCapability = { { name = "Plugin", value = 25 } },
	},
	brickColors = {
		colors = {
			{ number = 1, name = "White", color = { 0.95, 0.95, 0.95 } },
			{ number = 194, name = "Medium stone grey", color = { 0.64, 0.64, 0.65 } },
		},
		palette = table.create(128, 194),
	},
	fonts = { Legacy = { family = "rbxasset://fonts/families/LegacyArial.json", weight = "Regular", style = "Normal" } },
}

local function permits(...: string): { [string]: unknown }
	local out: { [string]: unknown } = {}
	for _, name in { ... } do
		out[name] = true
	end
	return out
end

type Extra = { script: string?, enum: string?, deprecated: string? }

local function property(
	owner: string,
	name: string,
	engineType: string,
	access: { [string]: unknown },
	extra: Extra?
): Member
	local fields: Extra = extra or {}
	return {
		Name = name,
		Owner = owner,
		Type = {
			EngineType = engineType,
			ScriptType = fields.script or engineType,
			EnumType = fields.enum,
		},
		Permits = access,
		Display = { DeprecationMessage = fields.deprecated },
	}
end

local CLASSES: { Member } = {
	{ Name = "Instance", Superclass = "Object", Permits = {}, Display = {} },
	{ Name = "GuiObject", Superclass = "Instance", Permits = {}, Display = {} },
	{ Name = "TextLabel", Superclass = "GuiObject", Permits = permits "New", Display = {} },
	{ Name = "Folder", Superclass = "Instance", Permits = permits "New", Display = {} },
	{ Name = "GuiService", Superclass = "Instance", Permits = permits "GetService", Display = {} },
	{ Name = "Hint", Superclass = "Instance", Permits = permits "New", Display = { DeprecationMessage = "old" } },
}

local PROPERTIES: { [string]: { Member } } = {
	Instance = {
		property("Instance", "Name", "string", permits("Read", "Write")),
		property("Instance", "Parent", "RefType", permits("Read", "Write"), { script = "Instance" }),
		property("Instance", "Archivable", "bool", permits("Read", "Write")),
		property("Instance", "UniqueId", "UniqueId", {}, { script = nil }),
	},
	GuiObject = {
		property("GuiObject", "Size", "UDim2", permits("Read", "Write")),
		property("GuiObject", "AbsoluteSize", "Vector2", permits "Read"),
		property("GuiObject", "Rotation", "float", permits("Read", "Write")),
		property("GuiObject", "ZIndex", "int", permits("Read", "Write")),
		property(
			"GuiObject",
			"Transparency",
			"float",
			permits("Read", "Write"),
			{ deprecated = "use BackgroundTransparency" }
		),
		property("GuiObject", "Pivot", "CoordinateFrame", permits("Read", "Write"), { script = "CFrame" }),
	},
	TextLabel = {
		property("TextLabel", "Text", "string", permits("Read", "Write")),
		property(
			"TextLabel",
			"TextXAlignment",
			"Enum",
			permits("Read", "Write"),
			{ enum = "TextXAlignment", script = "EnumItem" }
		),
		property("TextLabel", "FontFace", "Font", permits("Read", "Write")),
		property("TextLabel", "Image", "ContentId", permits("Read", "Write"), { script = "string" }),
		property("TextLabel", "Secret", "BinaryString", {}),
	},
	Folder = {},
	GuiService = { property("GuiService", "AutoSelectGuiEnabled", "bool", permits("Read", "Write")) },
	Hint = {},
	PluginGui = { property("PluginGui", "Title", "string", permits("Read", "Write")) },
}

local PLUGIN_SECURITY = table.freeze { capability = "Plugin" }
local ALL_SECURITY = table.freeze { capability = "All" }
local PLUGIN_CLASS: Member = { Name = "PluginGui", Superclass = "Instance", Permits = {}, Display = {} }
local HIDDEN_CLASS: Member = { Name = "Player", Superclass = "Instance", Permits = permits "New", Display = {} }

local function visible(filter: unknown): { Member }
	local classes = table.clone(CLASSES)
	if
		type(filter) == "table"
		and ((filter :: Fields).Security == PLUGIN_SECURITY or (filter :: Fields).Security == ALL_SECURITY)
	then
		table.insert(classes, PLUGIN_CLASS)
	end
	if type(filter) == "table" and (filter :: Fields).Security == ALL_SECURITY then
		table.insert(classes, HIDDEN_CLASS)
	end
	return classes
end

local function inherited(name: string): { Member }
	local out: { Member } = {}
	local current: string? = name
	while current ~= nil and PROPERTIES[current] ~= nil do
		for _, member in PROPERTIES[current] do
			table.insert(out, member)
		end
		local super: string? = nil
		for _, class in visible { Security = PLUGIN_SECURITY } do
			if class.Name == current then
				super = class.Superclass
			end
		end
		current = super
	end
	return out
end

local function instance(className: string): Fields
	local values: Fields = {
		Name = className,
		ClassName = className,
		Archivable = true,
		Destroy = function() end,
	}
	if className == "TextLabel" then
		values.Size = engine.UDim2.new(0, 100, 0, 20)
		values.AbsoluteSize = engine.Vector2.new(100, 20)
		values.Rotation = 0
		values.ZIndex = 1
		values.Transparency = 0
		values.Pivot = engine.CFrame.new(1, 2, 3)
		values.Text = "Label"
		values.TextXAlignment = engine.Enum.TextXAlignment.Center
		values.FontFace = engine.Font.fromEnum(engine.Enum.Font.Legacy)
		values.Image = ""
	end
	return values
end

local function studio(log: { string }?): Fields
	local reflection = {
		GetClasses = function(_: unknown, filter: unknown): { Member }
			return visible(filter)
		end,
		GetClass = function(_: unknown, name: string, filter: unknown): Member?
			for _, class in visible(filter) do
				if class.Name == name then
					return class
				end
			end
			return nil
		end,
		GetEventsOfClass = function(_: unknown, name: string, _filter: unknown): { Member }?
			if name == "Player" then
				return nil
			end
			return if name == "GuiObject" or name == "TextLabel"
				then {
					{ Name = "InputBegan", Owner = "GuiObject", Permits = permits "Listen", Display = {} },
					{ Name = "PrivateEvent", Owner = "GuiObject", Permits = {}, Display = {} },
				}
				else {}
		end,
		GetMethodsOfClass = function(_: unknown, name: string, _filter: unknown): { Member }?
			if name == "Player" then
				return nil
			end
			return if name == "GuiObject" or name == "TextLabel"
				then {
					{ Name = "NativeMethod", Owner = "GuiObject", Permits = permits "Call", Display = {} },
					{ Name = "PrivateMethod", Owner = "GuiObject", Permits = {}, Display = {} },
				}
				else {}
		end,
		GetPropertiesOfClass = function(_: unknown, name: string, filter: unknown): { Member }
			if log ~= nil then
				table.insert(log, name)
			end
			if name == "Player" then
				return {
					property("Player", "UserId", "int64", permits "Read"),
					property("Player", "PrivateValue", "string", {}),
				}
			end
			for _, class in visible(filter) do
				if class.Name == name then
					local members = inherited(name)
					if #visible(filter) > #CLASSES then
						table.insert(members, property(name, "PluginOnly", "bool", permits("Read", "Write")))
					end
					return members
				end
			end
			return {}
		end,
	}
	local game = {
		GetService = function(_: unknown, name: string): unknown
			assert(name == "ReflectionService", "the capture reads only ReflectionService")
			return reflection
		end,
		FindService = function(_: unknown, name: string): unknown
			return if name == "GuiService" then { AutoSelectGuiEnabled = true } else nil
		end,
	}
	return {
		game = game,
		Instance = {
			new = function(className: string): Fields
				assert(className == "TextLabel" or className == "Folder" or className == "Hint", "not creatable")
				return instance(className)
			end,
		},
		Enum = engine.Enum,
		BrickColor = engine.BrickColor,
		Font = engine.Font,
		typeof = engine.typeof,
		version = function(): string
			return "0.0.test"
		end,
		SecurityCapabilities = {
			new = function(...: unknown): unknown
				return ALL_SECURITY
			end,
			fromCurrent = function(): Fields
				return {
					Add = function(_: unknown, capability: unknown): unknown
						return if capability == engine.Enum.SecurityCapability.Plugin then PLUGIN_SECURITY else nil
					end,
				}
			end,
		},
	}
end

local function executor(globals: Fields, calls: { string }?): Lute.FixtureExecute
	return function(code: string): string
		if calls ~= nil then
			table.insert(calls, code)
		end
		return asString(Lute.chunk.load(code, { name = "studio", environment = globals })())
	end
end

local function thrown(body: () -> unknown): string
	local ok, problem = pcall(body)
	return if ok then "" else tostring(problem)
end

describe("Studio reflection export", function()
	it("keeps the named classes and their ancestors and drops an unknown root", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "TextLabel" } })
		local names: { string } = {}
		for name in snapshot.classes do
			table.insert(names, name)
		end
		table.sort(names)
		expect(names):toEqual { "GuiObject", "Instance", "TextLabel" }
		expect(snapshot.classes.Instance.superclass):toBe(nil)
		expect(snapshot.classes.TextLabel.superclass):toBe "GuiObject"
		expect(snapshot.schemaVersion):toBe(Roblox.reflectionSnapshot.SCHEMA_VERSION)
		expect(snapshot.engineVersion):toBe "0.0.test"
	end)

	it("exports plugin-security classes that the default reflection filter hides", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "PluginGui", "TextLabel" } })
		local plugin = snapshot.classes.PluginGui
		expect(plugin.superclass):toBe "Instance"
		expect(plugin.tags):toEqual { "NotCreatable" }
		expect(plugin.properties.Title.datatype):toBe "String"
		expect(plugin.properties.PluginOnly.datatype):toBe "Bool"
		expect(snapshot.classes.TextLabel.properties.PluginOnly):toBe(nil)
		expect(snapshot.classes.Instance.properties.PluginOnly):toBe(nil)
	end)

	it("uses all capabilities only for hidden class metadata", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "Player" } })
		expect(snapshot.classes.Player.superclass):toBe "Instance"
		expect(snapshot.classes.Player.tags):toEqual { "NotCreatable" }
		expect(snapshot.classes.Player.properties.UserId.scriptability):toBe "Read"
		expect(snapshot.classes.Player.properties.PrivateValue.scriptability):toBe "None"
		expect(snapshot.classes.Player.defaults):toEqual {}
		local bridge = Lute.fixture.bridge(snapshot)
		expect(pcall(function()
			bridge.engine.new "Player"
		end)):toBe(false)
		local player = bridge.environment.createEngineInstance "Player"
		expect(pcall(function()
			player.UserId = 7
		end)):toBe(false)
		expect(pcall(function()
			local _value = player.PrivateValue
		end)):toBe(false)
		bridge.environment.poke(player, "UserId", 7)
		expect(player.UserId):toBe(7)
	end)

	it("names datatypes, scriptability and tags the way the reflection database does", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "TextLabel", "GuiService" } })
		local gui = snapshot.classes.GuiObject.properties
		local label = snapshot.classes.TextLabel.properties
		local base = snapshot.classes.Instance.properties
		expect(base.Archivable):toEqual { datatype = "Bool", scriptability = "ReadWrite", tags = {} }
		expect(base.Name.datatype):toBe "String"
		expect(base.Parent.datatype):toBe "Ref"
		expect(base.UniqueId):toEqual { datatype = "UniqueId", scriptability = "None", tags = { "NotScriptable" } }
		expect(gui.AbsoluteSize):toEqual { datatype = "Vector2", scriptability = "Read", tags = { "ReadOnly" } }
		expect(gui.Rotation.datatype):toBe "Float32"
		expect(gui.ZIndex.datatype):toBe "Int32"
		expect(gui.Pivot.datatype):toBe "CFrame"
		expect(gui.Transparency.tags):toEqual { "Deprecated" }
		expect(label.TextXAlignment.datatype):toBe "Enum.TextXAlignment"
		expect(label.Image.datatype):toBe "ContentId"
		expect(label.Secret.scriptability):toBe "None"
		expect(snapshot.classes.Instance.tags):toEqual { "NotCreatable" }
		expect(snapshot.classes.TextLabel.tags):toEqual {}
		expect(snapshot.classes.GuiService.tags):toEqual { "NotCreatable", "Service" }
		expect(snapshot.classes.GuiObject.events):toEqual { "InputBegan" }
		expect(snapshot.classes.TextLabel.events):toEqual {}
		expect(snapshot.classes.GuiObject.methods):toEqual { "NativeMethod" }
		expect(snapshot.classes.TextLabel.methods):toEqual {}
	end)

	it("reads defaults from a new instance and encodes engine values", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "TextLabel", "GuiService" } })
		local defaults = snapshot.classes.TextLabel.defaults
		expect(defaults.Text):toBe "Label"
		expect(defaults.Size):toEqual { ["$"] = "UDim2", v = { 0, 100, 0, 20 } }
		expect(defaults.TextXAlignment):toEqual { ["$"] = "EnumItem", family = "TextXAlignment", name = "Center" }
		expect(defaults.FontFace):toEqual {
			["$"] = "Font",
			family = "rbxasset://fonts/families/LegacyArial.json",
			weight = "Regular",
			style = "Normal",
		}
		expect(defaults.Pivot):toEqual { ["$"] = "CFrame", v = { 1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1 } }
		expect(defaults.Name):toBe "TextLabel"
		expect(defaults.UniqueId):toBe(nil)
		expect(snapshot.classes.GuiObject.defaults):toEqual {}
		expect(snapshot.classes.GuiService.defaults):toEqual {}
	end)

	it("samples service values only when asked", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "GuiService" }, services = true })
		expect(snapshot.classes.GuiService.defaults):toEqual { AutoSelectGuiEnabled = true }
	end)

	it("keeps the referenced, requested and datatype enums with their values", function()
		local snapshot =
			Lute.fixture.exportStudio(executor(studio()), { classes = { "TextLabel" }, enums = { "KeyCode" } })
		local families: { string } = {}
		for name in assert(snapshot.enums) do
			table.insert(families, name)
		end
		table.sort(families)
		expect(families):toEqual {
			"ContentSourceType",
			"Font",
			"FontStyle",
			"FontWeight",
			"KeyCode",
			"TextXAlignment",
		}
		expect(assert(snapshot.enums).TextXAlignment):toEqual {
			{ name = "Left", value = 0 },
			{ name = "Right", value = 1 },
			{ name = "Center", value = 2 },
		}
	end)

	it("captures brick colors and the fonts of the Font enum", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "Folder" } })
		local colors = assert(snapshot.brickColors)
		expect(#colors.colors):toBe(2)
		expect(colors.colors[2].name):toBe "Medium stone grey"
		expect(#colors.palette):toBe(128)
		expect(snapshot.fonts):toEqual {
			Legacy = { family = "rbxasset://fonts/families/LegacyArial.json", weight = "Regular", style = "Normal" },
		}
	end)

	it("exports every class and enum without a filter", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { batchSize = 2 })
		local count = 0
		for _ in snapshot.classes do
			count += 1
		end
		expect(count):toBe(#CLASSES + 2)
		expect(snapshot.classes.Hint.tags):toEqual { "Deprecated" }
		expect(assert(snapshot.enums).Material ~= nil):toBe(true)
	end)

	it("reads each class once in batches of the requested size", function()
		local requested: { string } = {}
		local calls: { string } = {}
		Lute.fixture.exportStudio(executor(studio(requested), calls), { batchSize = 2 })
		table.sort(requested)
		expect(requested):toEqual {
			"Folder",
			"GuiObject",
			"GuiService",
			"Hint",
			"Instance",
			"Player",
			"PluginGui",
			"TextLabel",
		}
		expect(#calls):toBe(1 + 4 + 2 + 1)
	end)

	it("refuses an unknown class or enum before it reads a class", function()
		local calls: { string } = {}
		expect(thrown(function(): unknown
			return Lute.fixture.exportStudio(executor(studio(), calls), { classes = { "Nope" } })
		end)):toContain "Studio reflection has no class Nope"
		expect(#calls):toBe(1)
		expect(thrown(function(): unknown
			return Lute.fixture.exportStudio(executor(studio()), { classes = { "Folder" }, enums = { "Nope" } })
		end)):toContain "Studio has no enum Nope"
	end)

	it("writes a file that loads into a bridge with engine defaults and enums", function()
		local snapshot = Lute.fixture.exportStudio(executor(studio()), { classes = { "TextLabel", "Folder" } })
		if not fs.exists(DIRECTORY) then
			fs.createDirectory(DIRECTORY, { makeParents = true })
		end
		local path = DIRECTORY .. "/snapshot.json"
		Lute.fixture.save(path, snapshot)
		local loaded = Lute.fixture.load(path)
		local types = Roblox.reflectionSnapshot.library(loaded)
		local bridge = Lute.fixture.bridge(loaded)
		local label = bridge.environment.createInstance "TextLabel"
		expect(label.Text):toBe "Label"
		expect(label.TextXAlignment):toBe(types.Enum.TextXAlignment.Center)
		expect(label.Size):toBe(types.UDim2.fromOffset(100, 20))
		expect(label.FontFace):toBe(types.Font.fromEnum(types.Enum.Font.Legacy))
		label.TextXAlignment = types.Enum.TextXAlignment.Left
		expect(thrown(function(): unknown
			label.TextXAlignment = types.Enum.FontWeight.Bold
			return nil
		end)):toContain "requires Enum.TextXAlignment"
		expect(thrown(function(): unknown
			label.AbsoluteSize = types.Vector2.zero
			return nil
		end)):toContain "read-only property"
	end)
end)

describe("Studio probes", function()
	it("run the same sources in the engine and under Lute", function()
		local probes: { Lute.FixtureProbe } = {
			{ name = "sum", source = "return tostring(Vector2.new(1, 2) + Vector2.new(3, 4))" },
			{ name = "raise", source = "return Vector2.new().Nope" },
		}
		local globals = table.clone((engine :: unknown) :: Fields)
		globals.game = {
			GetService = function(): unknown
				return {
					JSONEncode = function(_: unknown, value: unknown): string
						return Lute.fixture.serialize(value)
					end,
				}
			end,
		}
		globals.version = function(): string
			return "0.0.test"
		end
		local recorded = Lute.fixture.probeStudio(executor(globals), probes)
		expect(recorded.engineVersion):toBe "0.0.test"
		expect(recorded.results):toEqual {
			sum = "ok: 4, 6",
			raise = "error: Nope is not a valid member of Vector2",
		}
		expect(Lute.fixture.probeLocal(globals, probes)):toEqual(recorded.results)
	end)
end)

return nil
