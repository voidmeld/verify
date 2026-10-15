--!strict

local Shape = require "../src/core/shape"

local Reflection = require "../src/roblox/reflection"

local function property(name: string, datatype: string, tags: { string }?): Reflection.Property
	return { Name = name, Datatype = datatype, Scriptability = "ReadWrite", Tags = tags or {} }
end

local function class(
	name: string,
	super: string?,
	properties: { Reflection.Property }?,
	tags: { string }?
): Reflection.Class
	local declared: { [string]: Reflection.Property } = {}
	for _, item in properties or ({} :: { Reflection.Property }) do
		declared[item.Name] = item
	end
	return { Name = name, Superclass = super, Properties = declared, DefaultProperties = {}, Tags = tags or {} }
end

local function database(classes: { [string]: Reflection.Class }): Reflection.Database
	return {
		GetClassNames = function(): { string }
			return Shape.sortedKeys(classes)
		end,
		GetClass = function(_: Reflection.Database, name: string): Reflection.Class?
			return classes[name]
		end,
	}
end

return { property = property, class = class, database = database }
