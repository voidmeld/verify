--!strict

local fs = require "@std/fs"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local Verify = require "../src/core"
local probes = require "./fixtures/datatype-probes"

local SNAPSHOT = "tests/fixtures/studio-reflection.json"
local RECORDED = "tests/fixtures/datatype-probes.json"

type Recorded = { engineVersion: string?, results: { [string]: string } }

local function thrown(body: () -> unknown): string
	local ok, problem = pcall(body)
	return if ok then "" else tostring(problem)
end

local function library(): Roblox.DatatypeLibrary
	return Roblox.reflectionSnapshot.library(Lute.fixture.load(SNAPSHOT))
end

local function environment(types: Roblox.DatatypeLibrary): { [string]: unknown }
	local globals = table.clone((types :: unknown) :: { [string]: unknown })
	globals.typeof = types.typeof
	return globals
end

local NUMBER = "[-+]?%d+%.?%d*[eE]?[-+]?%d*"

local function close(expected: string, actual: string, tolerance: number?): boolean
	if expected == actual then
		return true
	elseif tolerance == nil then
		return false
	end
	local left: { string } = {}
	local right: { string } = {}
	for token in string.gmatch(expected, NUMBER) do
		table.insert(left, token)
	end
	for token in string.gmatch(actual, NUMBER) do
		table.insert(right, token)
	end
	local shape = (string.gsub(expected, NUMBER, "#"))
	if shape ~= (string.gsub(actual, NUMBER, "#")) or #left ~= #right then
		return false
	end
	for index, token in left do
		local a, b = tonumber(token) :: number, tonumber(right[index]) :: number
		if math.abs(a - b) > tolerance * math.max(1, math.abs(a), math.abs(b)) then
			return false
		end
	end
	return true
end

return function(suite: Verify.Harness)
	suite:suite("Roblox datatypes compared with Studio", function()
		suite:case("every probe gives the result that Studio recorded", function(check)
			local recorded = Lute.parse(fs.readFileToString(RECORDED)) :: Recorded
			check:expect(type(recorded.engineVersion)):toBe "string"
			local local_ = Lute.fixture.probeLocal(environment(library()), probes)
			local mismatches: { string } = {}
			for _, probe in probes do
				local expected = recorded.results[probe.name]
				local actual = local_[probe.name]
				if expected == nil or not close(expected, actual, probe.tolerance) then
					table.insert(
						mismatches,
						("%s\n  studio: %s\n  verify: %s"):format(probe.name, tostring(expected), actual)
					)
				end
			end
			check:expect(table.concat(mismatches, "\n")):toBe ""
		end)

		suite:case("the recorded results name exactly the current probes", function(check)
			local recorded = Lute.parse(fs.readFileToString(RECORDED)) :: Recorded
			local names: { [string]: boolean } = {}
			for _, probe in probes do
				check:expect(names[probe.name]):toBe(nil)
				names[probe.name] = true
			end
			local stale: { string } = {}
			for name in recorded.results do
				if not names[name] then
					table.insert(stale, name)
				end
			end
			check:expect(stale):toEqual {}
			check:expect(#probes > 100):toBe(true)
		end)
	end)

	suite:suite("datatype values", function()
		suite:case("are userdata that Verify names like the engine does", function(check)
			local types = library()
			local values: { unknown } = {
				types.Vector2.zero,
				types.Vector3.one,
				types.CFrame.new(),
				types.Color3.new(),
				types.UDim.new(),
				types.UDim2.new(),
				types.Rect.new(),
				types.NumberRange.new(1),
				types.NumberSequence.new(1),
				types.ColorSequence.new(types.Color3.new()),
				types.BrickColor.new(1),
				types.Font.new "x",
				types.TweenInfo.new(),
				types.Content.none,
				types.Enum.FontWeight.Bold,
				types.Enum.FontWeight,
				types.Enum,
			}
			local names: { string } = {}
			for _, value in values do
				check:expect(type(value)):toBe "userdata"
				table.insert(names, Roblox.typeName(value))
			end
			check:expect(names):toEqual {
				"Vector2",
				"Vector3",
				"CFrame",
				"Color3",
				"UDim",
				"UDim2",
				"Rect",
				"NumberRange",
				"NumberSequence",
				"ColorSequence",
				"BrickColor",
				"Font",
				"TweenInfo",
				"Content",
				"EnumItem",
				"Enum",
				"Enums",
			}
			check:expect(types.typeof(5)):toBe "number"
			check:expect(types.typeName {}):toBe(nil)
			check
				:expect(thrown(function(): unknown
					return table.clone((types.Vector2.zero :: unknown) :: {})
				end) ~= "")
				:toBe(true)
		end)

		suite:case("share enum items between the snapshot defaults and the bound library", function(check)
			local snapshot = Lute.fixture.load(SNAPSHOT)
			local types = Roblox.reflectionSnapshot.library(snapshot)
			local database = Roblox.reflectionSnapshot.database(snapshot)
			local label = database:GetClass "TextLabel" :: Roblox.ReflectionClass
			local alignment = label.DefaultProperties.TextXAlignment
			check:expect(rawequal(alignment, types.Enum.TextXAlignment.Center)):toBe(true)
			check:expect(Roblox.reflectionSnapshot.library(snapshot) == types):toBe(true)
			check:expect(types.Enum.TextXAlignment:FromValue(0)):toBe(types.Enum.TextXAlignment.Left)
			check
				:expect(thrown(function(): unknown
					return ((types.Enum :: unknown) :: { [string]: unknown }).KeyCode
				end))
				:toContain 'KeyCode is not a valid member of "Enum"'
		end)

		suite:case("keep the permissive default library and refuse catalog data it lacks", function(check)
			local types = Roblox.datatypes
			check:expect(tostring(types.Enum.Material.Plastic)):toBe "Enum.Material.Plastic"
			check:expect(types.Enum.Material.Plastic == types.Enum.Material.Plastic):toBe(true)
			check:expect(types.enumType(types.Enum.KeyCode.A)):toBe "KeyCode"
			check
				:expect(thrown(function(): unknown
					return types.BrickColor.new(1)
				end))
				:toContain "requires a reflection snapshot with brickColors"
			check
				:expect(thrown(function(): unknown
					return types.Font.fromEnum(types.Enum.Font.Gotham)
				end))
				:toContain "requires a reflection snapshot with fonts"
		end)

		suite:case("bind a library to a catalog that the caller supplies", function(check)
			local types = Roblox.datatypes.create {
				enums = { Shape = { { name = "Round", value = 2 }, { name = "Square", value = 5 } } },
			}
			local shape = ((types.Enum :: unknown) :: { [string]: Roblox.DatatypeEnumCategory }).Shape
			check:expect(#shape:GetEnumItems()):toBe(2)
			check:expect(shape:FromValue(5)):toBe(shape.Square)
			check:expect(shape.Round.Value):toBe(2)
			check:expect(shape.Round:IsA "Shape"):toBe(true)
			check:expect(#types.Enum:GetEnums()):toBe(1)
		end)
	end)
end
