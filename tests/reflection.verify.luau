--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Fixture = require "./reflection-fixture"

local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"

local property = Fixture.property
local function database(): Reflection.Database
	local classes: { [string]: Reflection.Class } = {
		Instance = {
			Name = "Instance",
			Properties = { Name = property("Name", "String"), Archivable = property("Archivable", "Bool") },
			DefaultProperties = { Name = "Instance", Archivable = true },
			Tags = { "NotCreatable" },
		},
		Folder = { Name = "Folder", Superclass = "Instance", Properties = {}, DefaultProperties = {}, Tags = {} },
		Part = {
			Name = "Part",
			Superclass = "Instance",
			Properties = {
				Size = property("Size", "Vector3"),
				Material = property("Material", "Enum.Material"),
				Mass = property("Mass", "Float32", { "ReadOnly" }),
				Secret = { Name = "Secret", Datatype = "String", Scriptability = "None", Tags = {} },
				WriteOnly = { Name = "WriteOnly", Datatype = "String", Scriptability = "Write", Tags = {} },
			},
			DefaultProperties = { Mass = 1 },
			Tags = {},
		},
		Model = {
			Name = "Model",
			Superclass = "Instance",
			Properties = { PrimaryPart = property("PrimaryPart", "Ref"), TypedPart = property("TypedPart", "Part") },
			DefaultProperties = {},
			Tags = {},
		},
	}
	return {
		GetClassNames = function()
			return { "Model", "Folder", "Part", "Instance" }
		end,
		GetClass = function(_, name)
			return classes[name]
		end,
	}
end
local function succeeds(callback: () -> ...unknown): boolean
	return (pcall(callback))
end

describe("reflection adapter", function()
	it("protected and write-only reads cannot escape through doubles or computed getters", function()
		local computed: { [string]: Environment.Computed } = {
			["Part.Secret"] = function()
				return "leaked"
			end,
		}
		local env = Reflection.create {
			database = database(),
			typeName = typeof,
			functionDoubles = true,
			computed = computed,
		}
		local part = env.createInstance "Part"
		part.WriteOnly = "accepted"
		expect(succeeds(function()
			return part.WriteOnly
		end)):toBe(false)
		expect(succeeds(function()
			return part.Secret
		end)):toBe(false)
		expect(succeeds(function()
			part.Secret = "denied"
		end)):toBe(false)
		expect(succeeds(function()
			part.Mass = function() end
		end)):toBe(false)
	end)
	it("inherits defaults and rejects unknown, readonly and invalid properties before mutation", function()
		local env = Reflection.create { database = database(), typeName = typeof }
		local part = env.createInstance "Part"
		expect(part.Name):toBe "Part"
		expect(part.Archivable):toBe(true)
		expect(pcall(function()
			part.Name = 42
		end)):toBe(false)
		expect(part.Name):toBe "Part"
		expect(pcall(function()
			part.Mass = 2
		end)):toBe(false)
		expect(pcall(function()
			part.Unknown = true
		end)):toBe(false)
		expect(pcall(function()
			env.createInstance "Instance"
		end)):toBe(false)
		env.poke(part, "Mass", 2)
		expect(part.Mass):toBe(2)
	end)
	it("checks native datatypes, enum identity and reference classes", function()
		local vector = { kind = "Vector3" }
		local material = { kind = "EnumItem", enum = "Enum.Material" }
		local env = Reflection.create {
			database = database(),
			typeName = function(value)
				if type(value) == "table" then
					return (value :: { kind: string }).kind
				end
				return typeof(value)
			end,
			enumType = function(value)
				return (value :: { enum: string }).enum
			end,
			referenceClass = function(_, key)
				return if key == "PrimaryPart" then "Part" else nil
			end,
		}
		local part, model, folder = env.createInstance "Part", env.createInstance "Model", env.createInstance "Folder"
		part.Size = vector
		part.Material = material
		expect(pcall(function()
			part.Material = { kind = "EnumItem", enum = "Enum.KeyCode" }
		end)):toBe(false)
		expect(pcall(function()
			part.Size = "Vector3"
		end)):toBe(false)
		model.PrimaryPart = part
		model.TypedPart = part
		expect(pcall(function()
			model.PrimaryPart = folder
		end)):toBe(false)
		expect(pcall(function()
			model.TypedPart = folder
		end)):toBe(false)
		expect(pcall(function()
			model.PrimaryPart = {}
		end)):toBe(false)
		model.PrimaryPart = nil
		expect(model.PrimaryPart):toBe(nil)
	end)
	it("composes custom validation for reflected and overlay properties", function()
		local writes = 0
		local extra: { [string]: unknown } = { Enabled = true }
		local overlay: Environment.ClassSpec = { properties = extra }
		local env = Reflection.create {
			database = database(),
			typeName = typeof,
			classes = { Part = overlay },
			validateProperty = function(_, key, value)
				writes += 1
				assert(key ~= "Enabled" or value == true, "disabled")
			end,
		}
		local part = env.createInstance "Part"
		part.Name = "Valid"
		expect(pcall(function()
			part.Enabled = false
		end)):toBe(false)
		expect(part.Enabled):toBe(true)
		part.Parent = env.createInstance "Folder"
		expect(writes):toBe(3)
	end)
	it("reads a declared property with no stored default as unset and keeps false and nil", function()
		local db = database()
		local part = db:GetClass "Part"
		assert(part)
		part.Properties.Locked = property("Locked", "Bool")
		part.Properties.Anchored = property("Anchored", "Bool")
		part.DefaultProperties.Anchored = false
		local env = Reflection.create { database = db, typeName = typeof }
		local instance = env.createInstance "Part"
		expect(instance.Locked):toBe(nil)
		expect(instance.Anchored):toBe(false)
		expect(env.createInstance("Model").PrimaryPart):toBe(nil)
		expect(instance.Mass):toBe(1)
	end)
	it("applies a declared default only where the database stores none and lets a double win", function()
		local db = database()
		local part = db:GetClass "Part"
		assert(part)
		part.Properties.Locked = property("Locked", "Bool")
		local declared: { [string]: unknown } = { Locked = true, Mass = 9, Extra = 3 }
		local env = Reflection.create {
			database = db,
			typeName = typeof,
			classes = { Part = { properties = declared } },
		}
		local instance = env.createInstance "Part"
		expect(instance.Locked):toBe(true)
		expect(instance.Mass):toBe(1)
		expect(instance.Extra):toBe(3)
		expect(instance.Size):toBe(nil)
		env.defineClass("Part", { super = "Instance", properties = { Size = 5 } }, { replace = true })
		expect(env.createInstance("Part").Size):toBe(5)
	end)
	it("rejects missing and cyclic reflection inheritance", function()
		local db = database()
		local model = db:GetClass "Model"
		assert(model)
		model.Superclass = "Missing"
		expect(pcall(function()
			Reflection.create { database = db, typeName = typeof }
		end)):toBe(false)
		model.Superclass = "Model"
		expect(pcall(function()
			Reflection.create { database = db, typeName = typeof }
		end)):toBe(false)
	end)
end)

return nil
