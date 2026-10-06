--!strict

local Core = require "../src/core"
local Environment = require "../src/roblox/environment"
local Reflection = require "../src/roblox/reflection"

local function property(name: string, datatype: string, tags: { string }?): Reflection.Property
	return { Name = name, Datatype = datatype, Scriptability = "ReadWrite", Tags = tags or {} }
end
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
return function(suite: Core.Harness)
	suite:suite("reflection adapter", function()
		suite:case(
			"inherits defaults and rejects unknown, readonly and invalid properties before mutation",
			function(check)
				local env = Reflection.create { database = database(), typeName = typeof }
				local part = env.createInstance "Part"
				check:expect(part.Name):toBe "Part"
				check:expect(part.Archivable):toBe(true)
				check
					:expect(pcall(function()
						part.Name = 42
					end))
					:toBe(false)
				check:expect(part.Name):toBe "Part"
				check
					:expect(pcall(function()
						part.Mass = 2
					end))
					:toBe(false)
				check
					:expect(pcall(function()
						part.Unknown = true
					end))
					:toBe(false)
				check
					:expect(pcall(function()
						env.createInstance "Instance"
					end))
					:toBe(false)
				env.poke(part, "Mass", 2)
				check:expect(part.Mass):toBe(2)
			end
		)
		suite:case("checks native datatypes, enum identity and reference classes", function(check)
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
			local part, model, folder =
				env.createInstance "Part", env.createInstance "Model", env.createInstance "Folder"
			part.Size = vector
			part.Material = material
			check
				:expect(pcall(function()
					part.Material = { kind = "EnumItem", enum = "Enum.KeyCode" }
				end))
				:toBe(false)
			check
				:expect(pcall(function()
					part.Size = "Vector3"
				end))
				:toBe(false)
			model.PrimaryPart = part
			model.TypedPart = part
			check
				:expect(pcall(function()
					model.PrimaryPart = folder
				end))
				:toBe(false)
			check
				:expect(pcall(function()
					model.TypedPart = folder
				end))
				:toBe(false)
			check
				:expect(pcall(function()
					model.PrimaryPart = {}
				end))
				:toBe(false)
			model.PrimaryPart = nil
			check:expect(model.PrimaryPart):toBe(nil)
		end)
		suite:case("composes custom validation for reflected and overlay properties", function(check)
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
			check
				:expect(pcall(function()
					part.Enabled = false
				end))
				:toBe(false)
			check:expect(part.Enabled):toBe(true)
			part.Parent = env.createInstance "Folder"
			check:expect(writes):toBe(3)
		end)
		suite:case("reads a declared property with no stored default as unset and keeps false and nil", function(check)
			local db = database()
			local part = db:GetClass "Part"
			assert(part)
			part.Properties.Locked = property("Locked", "Bool")
			part.Properties.Anchored = property("Anchored", "Bool")
			part.DefaultProperties.Anchored = false
			local env = Reflection.create { database = db, typeName = typeof }
			local instance = env.createInstance "Part"
			check:expect(instance.Locked):toBe(nil)
			check:expect(instance.Anchored):toBe(false)
			check:expect(env.createInstance("Model").PrimaryPart):toBe(nil)
			check:expect(instance.Mass):toBe(1)
		end)
		suite:case(
			"applies a declared default only where the database stores none and lets a double win",
			function(check)
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
				check:expect(instance.Locked):toBe(true)
				check:expect(instance.Mass):toBe(1)
				check:expect(instance.Extra):toBe(3)
				check:expect(instance.Size):toBe(nil)
				env.defineClass("Part", { super = "Instance", properties = { Size = 5 } }, { replace = true })
				check:expect(env.createInstance("Part").Size):toBe(5)
			end
		)
		suite:case("rejects missing and cyclic reflection inheritance", function(check)
			local db = database()
			local model = db:GetClass "Model"
			assert(model)
			model.Superclass = "Missing"
			check
				:expect(pcall(function()
					Reflection.create { database = db, typeName = typeof }
				end))
				:toBe(false)
			model.Superclass = "Model"
			check
				:expect(pcall(function()
					Reflection.create { database = db, typeName = typeof }
				end))
				:toBe(false)
		end)
	end)
end
