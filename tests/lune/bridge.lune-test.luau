--!strict

local load = require :: (string) -> unknown

local LuneReflection = require "../../src/lune/reflection"
local Reflection = require "../../src/roblox/reflection"
local Environment = require "../../src/roblox/environment"
local UiFakes = require "../../src/roblox/ui-fakes"
local Verify = require "../../src/core"

type Native = LuneReflection.Native<unknown, unknown, unknown, unknown, unknown, unknown> & {
	Instance: { new: (string) -> unknown },
	Enum: { Material: { Plastic: unknown, Wood: unknown }, KeyCode: { A: unknown }, FormFactor: { Brick: unknown } },
}

local roblox = load "@lune/roblox" :: Native

local function succeeds(body: () -> unknown): boolean
	return (pcall(body))
end

local function strippedDatabase(): Reflection.Database
	local real = roblox.getReflectionDatabase()
	return {
		GetClassNames = function(): { string }
			return real:GetClassNames()
		end,
		GetClass = function(_: Reflection.Database, name: string): Reflection.Class?
			local class = real:GetClass(name)
			if class == nil then
				return nil
			end
			return {
				Name = class.Name,
				Superclass = class.Superclass,
				Properties = class.Properties,
				DefaultProperties = {},
				Tags = class.Tags,
			}
		end,
	}
end

local function bridgeNative(
	withInstance: boolean
): LuneReflection.Native<unknown, unknown, unknown, unknown, unknown, unknown>
	local stripped = strippedDatabase()
	return {
		getReflectionDatabase = function(): Reflection.Database
			return stripped
		end,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		CFrame = roblox.CFrame,
		Instance = if withInstance then roblox.Instance else nil,
	}
end

local function call(object: Environment.Instance, name: string, ...: unknown): unknown
	return (object[name] :: Environment.Method)(object, ...)
end

return function(suite: Verify.Harness)
	suite:suite("lune reflection fixture bridge (real @lune/roblox)", function()
		suite:case("validates simulated instances against the real class database and native datatypes", function(check)
			local bridge = LuneReflection.create()
			local env = bridge.environment
			local part = env.createInstance "Part"
			check:expect(part.Anchored):toBe(false)
			part.Size = roblox.Vector3.new(2, 3, 4)
			part.Material = roblox.Enum.Material.Plastic
			check:expect(typeof(part.Size)):toBe "Vector3"
			check
				:expect(succeeds(function(): unknown
					part.Material = roblox.Enum.KeyCode.A
					return nil
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					part.Size = roblox.Vector2.new(1, 1)
					return nil
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					part.Anchored = 1
					return nil
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					part.NotAProperty = true
					return nil
				end))
				:toBe(false)
			local label = env.createInstance "TextLabel"
			label.BackgroundColor3 = roblox.Color3.new(1, 0, 0)
			label.Size = roblox.UDim2.new(0, 10, 0, 20)
			check
				:expect(succeeds(function(): unknown
					label.AbsoluteSize = roblox.Vector2.new(1, 2)
					return nil
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					label.Size = roblox.Vector3.new(1, 2, 3)
					return nil
				end))
				:toBe(false)
		end)

		suite:case("resolves class hierarchy through the real superclass chain", function(check)
			local bridge = LuneReflection.create()
			local env = bridge.environment
			local frame = env.createInstance "Frame"
			local button = env.createInstance "TextButton"
			button.Parent = frame
			check:expect(button:IsA "GuiObject"):toBe(true)
			check:expect(button:IsA "GuiButton"):toBe(true)
			check:expect(button:IsA "BasePart"):toBe(false)
			check:expect(frame:FindFirstChildWhichIsA "GuiObject" == button):toBe(true)
			check
				:expect(succeeds(function(): unknown
					return env.createInstance "GuiObject"
				end))
				:toBe(false)
			check
				:expect(succeeds(function(): unknown
					return env.createInstance "NoSuchClass"
				end))
				:toBe(false)
		end)

		suite:case("provides every UI fake the real database knows", function(check)
			local bridge = LuneReflection.create()
			check:expect(bridge.unavailable):toEqual {}
			local env = bridge.environment
			local box = env.createInstance "TextBox"
			call(box, "CaptureFocus")
			check:expect((bridge.ui :: UiFakes.Controller).focused() == box):toBe(true)
			local button = env.createInstance "TextButton"
			local activated = 0
			local signal = button.Activated :: Environment.Signal<...unknown>
			signal:Connect(function()
				activated += 1
			end)
			env.fire(button, "Activated")
			check:expect(activated):toBe(1)
			local panel = env.createInstance("Frame", { Visible = false })
			local hidden = env.createInstance("TextBox", { Parent = panel })
			check
				:expect(succeeds(function(): unknown
					return call(hidden, "CaptureFocus")
				end))
				:toBe(false)
		end)

		suite:case("clones preserve UI fake state over real classes", function(check)
			local bridge = LuneReflection.create()
			local env = bridge.environment
			local root = env.createInstance "Folder"
			local sheet = env.createInstance("StyleSheet", { Parent = root })
			local rule = env.createInstance("StyleRule", { Parent = sheet })
			call(rule, "SetProperty", "BackgroundColor3", roblox.Color3.new(0, 1, 0))
			local copy = root:Clone() :: Environment.Instance
			local copiedRule = (copy:FindFirstChildOfClass "StyleSheet" :: Environment.Instance):FindFirstChildOfClass "StyleRule"
			check
				:expect(typeof(call(copiedRule :: Environment.Instance, "GetProperty", "BackgroundColor3")))
				:toBe "Color3"
		end)

		suite:case("serves native datatypes through the engine seam and refuses unfired faults", function(check)
			local bridge = LuneReflection.create()
			local vector = bridge.engine.datatypes.Vector3
			check:expect(typeof(if vector ~= nil then vector(1, 2, 3) else nil)):toBe "Vector3"
			check:expect(bridge.engine.typeName(roblox.UDim2.new(0, 1, 0, 1))):toBe "UDim2"
			local object = bridge.engine.new "Part"
			check:expect(typeof(object)):toBe "table"
			bridge.faults.inject("setProperty", 1)
			check:expect(succeeds(bridge.faults.assertConsumed)):toBe(false)
			check
				:expect(succeeds(function(): unknown
					object.Name = "x"
					return nil
				end))
				:toBe(false)
			check:expect(succeeds(bridge.faults.assertConsumed)):toBe(true)
		end)

		suite:case("names the UI fake classes a narrowed real database lacks", function(check)
			local bridge = LuneReflection.createFrom {
				getReflectionDatabase = function(): Reflection.Database
					local real = roblox.getReflectionDatabase()
					return {
						GetClassNames = function(): { string }
							local names: { string } = {}
							for _, name in real:GetClassNames() do
								if name ~= "Path2D" and name ~= "StyleSheet" then
									table.insert(names, name)
								end
							end
							return names
						end,
						GetClass = function(_, name: string): Reflection.Class?
							if name == "Path2D" or name == "StyleSheet" then
								return nil
							end
							return real:GetClass(name)
						end,
					}
				end,
				Vector2 = roblox.Vector2,
				Vector3 = roblox.Vector3,
				Color3 = roblox.Color3,
				UDim = roblox.UDim,
				UDim2 = roblox.UDim2,
				CFrame = roblox.CFrame,
			}
			check:expect(bridge.unavailable):toEqual { "Path2D", "StyleSheet" }
			check
				:expect(succeeds(function(): unknown
					return bridge.environment.createInstance "StyleSheet"
				end))
				:toBe(false)
			check:expect(bridge.environment.createInstance("TextBox").ClassName):toBe "TextBox"
		end)

		suite:case("reads a default the database does not store from a real Instance.new", function(check)
			local native = bridgeNative(true)
			local bridge = LuneReflection.createFrom(native)
			local label = bridge.environment.createInstance "TextLabel"
			local expected = (roblox.Instance.new "TextLabel" :: unknown) :: { [string]: unknown }
			local compared = 0
			for name in (strippedDatabase():GetClass "TextLabel" :: Reflection.Class).Properties do
				local ok, value = pcall(function(): unknown
					return expected[name]
				end)
				local kind: string = typeof(value)
				if name ~= "Name" and name ~= "Parent" and ok and value ~= nil and kind ~= "Instance" then
					check:expect(label[name] == value):toBe(true)
					compared += 1
				end
			end
			check:expect(compared > 10):toBe(true)
			check:expect(label.Text):toBe "Label"
			check:expect(bridge.environment.createInstance("Part").Anchored):toBe(false)
			check:expect(label.Parent):toBe(nil)
			label.Text = "changed"
			(label.ResetPropertyToDefault :: (Environment.Instance, string) -> ())(label, "Text")
			check:expect(label.Text):toBe "Label"
		end)

		suite:case("the default Lune fixture reads a default that the real database omits", function(check)
			local part = LuneReflection.create().environment.createInstance "Part"
			check:expect(part.FormFactor == roblox.Enum.FormFactor.Brick):toBe(true)
			local silent = LuneReflection.create {
				defaultProperty = function(): unknown
					return nil
				end,
			}
			check:expect(silent.environment.createInstance("Part").FormFactor):toBe(nil)
		end)

		suite:case("a database without stored defaults and no real Instance reads nil", function(check)
			local bridge = LuneReflection.createFrom(bridgeNative(false))
			local label = bridge.environment.createInstance "TextLabel"
			check:expect(label.Text):toBe(nil)
			check:expect(label.Visible):toBe(nil)
		end)

		suite:case("a supplied defaultProperty hook replaces the native read", function(check)
			local native = bridgeNative(true)
			local bridge = LuneReflection.createFrom(native, {
				defaultProperty = function(_className: string, property: string): unknown
					if property == "Text" then
						return "hooked"
					end
					return nil
				end,
			})
			local label = bridge.environment.createInstance "TextLabel"
			check:expect(label.Text):toBe "hooked"
			check:expect(label.Visible):toBe(nil)
		end)
	end)
end
