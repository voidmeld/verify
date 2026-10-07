--!strict

local load = require :: (string) -> unknown
local fs = load "@lune/fs" :: { readFile: (string) -> string }

local Export = require "../../src/lune/reflection-export"
local FixtureBridge = require "../../src/roblox/fixture-bridge"
local LuneReflection = require "../../src/lune/reflection"
local Reflection = require "../../src/roblox/reflection"
local Snapshot = require "../../src/roblox/reflection-snapshot"
local Verify = require "../../src/core"

type Native = LuneReflection.Native<unknown, unknown, unknown, unknown, unknown, unknown> & {
	Enum: { Material: { Plastic: unknown }, KeyCode: { A: unknown } },
}

local roblox = load "@lune/roblox" :: Native
local CLASSES = { "Part", "TextLabel", "Frame", "Model", "Folder" }
local ENCODABLE: { [string]: boolean } = {
	boolean = true,
	number = true,
	string = true,
	Vector3 = true,
	Vector2 = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	CFrame = true,
	EnumItem = true,
}

local function accepts(body: () -> unknown): boolean
	return (pcall(body))
end

local function verdicts(bridge: FixtureBridge.Bridge, vector: unknown, material: unknown, wrong: unknown): { boolean }
	local env = bridge.environment
	local part = env.createInstance "Part"
	local label = env.createInstance "TextLabel"
	return {
		accepts(function(): unknown
			part.Size = vector
			return nil
		end),
		accepts(function(): unknown
			part.Size = "invalid"
			return nil
		end),
		accepts(function(): unknown
			part.Material = material
			return nil
		end),
		accepts(function(): unknown
			part.Material = wrong
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
end

return function(suite: Verify.Harness)
	suite:suite("reflection snapshot exported from @lune/roblox", function()
		local snapshot = Export.create { classes = CLASSES }

		suite:case("the committed fixture is the current export", function(check)
			local committed = fs.readFile "tests/fixtures/reflection-snapshot.json"
			check:expect(Export.serialize(snapshot) .. "\n"):toBe(committed)
		end)

		suite:case("agrees with the native database on classes, properties and defaults", function(check)
			local native = roblox.getReflectionDatabase()
			local loaded = Snapshot.database(snapshot)
			for _, name in loaded:GetClassNames() do
				local expected = native:GetClass(name)
				local actual = loaded:GetClass(name)
				check:expect(actual ~= nil and expected ~= nil):toBe(true)
				if actual ~= nil and expected ~= nil then
					check:expect(actual.Superclass):toBe(expected.Superclass)
					for key, property in expected.Properties do
						check:expect(actual.Properties[key].Datatype):toBe(property.Datatype)
						check:expect(actual.Properties[key].Scriptability):toBe(property.Scriptability)
					end
				end
			end
			local function default(database: Reflection.Database, class: string, key: string): unknown
				return ((database:GetClass(class) :: Reflection.Class).DefaultProperties :: { [string]: unknown })[key]
			end
			local function field(value: unknown, key: string): unknown
				return (value :: { [string]: unknown })[key]
			end
			check:expect(default(loaded, "Part", "Anchored")):toBe(default(native, "Part", "Anchored"))
			check:expect(field(default(loaded, "Part", "Size"), "X")):toBe(field(default(native, "Part", "Size"), "X"))
			check
				:expect(field(default(loaded, "TextLabel", "TextXAlignment"), "_enum"))
				:toBe(field(default(native, "TextLabel", "TextXAlignment"), "Name"))
			check:expect(field(default(loaded, "TextLabel", "TextXAlignment"), "_family")):toBe "TextXAlignment"
		end)

		suite:case(
			"instances read the same defaults from the snapshot and the live database, missing ones unset",
			function(check)
				local native = roblox.getReflectionDatabase()
				local live = LuneReflection.create({
					defaultProperty = function(): unknown
						return nil
					end,
				}).environment
				local loaded = Snapshot.bridge(snapshot).environment
				local checked, unset = 0, 0
				for _, name in CLASSES do
					local liveObject = live.createInstance(name)
					local loadedObject = loaded.createInstance(name)
					local current: string? = name
					while current ~= nil do
						local class = native:GetClass(current) :: Reflection.Class
						for key in class.Properties do
							if key ~= "ClassName" and key ~= "Parent" then
								local expected = live.propertyOf(liveObject, key)
								local actual = loaded.propertyOf(loadedObject, key)
								local label = name .. "." .. key
								local encodable = expected == nil or ENCODABLE[typeof(expected)] == true
								check
									:expect(label .. (if actual == nil then " unset" else " set"))
									:toBe(label .. (if expected == nil or not encodable then " unset" else " set"))
								local kind = type(expected)
								if kind == "boolean" or kind == "number" or kind == "string" then
									check:expect(actual):toBe(expected)
								end
								checked += 1
								if expected == nil then
									unset += 1
								end
							end
						end
						current = class.Superclass
					end
				end
				check:expect(checked > 100):toBe(true)
				check:expect(unset > 0):toBe(true)
				check:expect(live.propertyOf(live.createInstance "Model", "PrimaryPart")):toBe(nil)
				check:expect(loaded.propertyOf(loaded.createInstance "Model", "PrimaryPart")):toBe(nil)
			end
		)

		suite:case("accepts and refuses the same property writes as the native bridge", function(check)
			local nativeVerdicts = verdicts(
				LuneReflection.create(),
				roblox.Vector3.new(1, 2, 3),
				roblox.Enum.Material.Plastic,
				roblox.Enum.KeyCode.A
			)
			local Datatypes = require "../../src/roblox/datatypes"
			local snapshotVerdicts = verdicts(
				Snapshot.bridge(snapshot),
				Datatypes.Vector3.new(1, 2, 3),
				Datatypes.Enum.Material.Plastic,
				Datatypes.Enum.KeyCode.A
			)
			check:expect(snapshotVerdicts):toEqual(nativeVerdicts)
			check:expect(nativeVerdicts):toEqual { true, false, true, false, false, false, false }
		end)

		suite:case("refuses a snapshot of another schema", function(check)
			check
				:expect(accepts(function(): unknown
					return Snapshot.database { schemaVersion = 99, classes = {} }
				end))
				:toBe(false)
		end)
	end)
end
