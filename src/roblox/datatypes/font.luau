--!strict

local Enum = require "./enum"
local Names = require "./names"

type EnumItem = Enum.EnumItem
type Enums = Enum.Enums

local FontValueFields: { Family: string, Weight: EnumItem, Style: EnumItem, Bold: boolean }
local FontValueMeta: { __eq: (FontValue, FontValue) -> boolean, __tostring: (FontValue) -> string }

export type FontValue = typeof(setmetatable(FontValueFields, FontValueMeta))

export type FontEntry = { family: string, weight: string, style: string }
export type FontCatalog = { [string]: FontEntry }

export type FontConstructor = {
	new: (family: string, weight: EnumItem?, style: EnumItem?) -> FontValue,
	fromName: (name: string, weight: EnumItem?, style: EnumItem?) -> FontValue,
	fromId: (id: number | string, weight: EnumItem?, style: EnumItem?) -> FontValue,
	fromEnum: (font: EnumItem) -> FontValue,
}

local ENUMS = {}
local BOLD = 600
local fontEnums: { [unknown]: Enums } = {}
Names.weak(fontEnums)

local FontKind = Names.behavior("Font", { quoted = true })

local function checkItem(value: unknown, family: string): EnumItem
	if not Enum.isItem(value) then
		Names.argument(2, "Enum." .. family, value)
	end
	local found = Enum.enumType(value)
	if found ~= family then
		error(("Invalid type '%s' for enum '%s'"):format(found, family), 4)
	end
	return Enum.itemValue(value)
end

local function quoted(key: unknown): string
	return "'" .. tostring(key) .. "'"
end

FontKind.fields.__index = function(fields: Names.Fields, key: unknown): unknown
	if key == "Bold" then
		local weight = Enum.itemValue(fields.Weight).Value
		if weight == nil then
			error("Font.Bold requires an enum catalog with FontWeight values", 2)
		end
		return weight >= BOLD
	end
	return Names.invalid(quoted(key), "Font")
end

FontKind.meta.__newindex = function(value: unknown, key: unknown, assigned: unknown)
	local fields = Names.fields(value)
	if key == "Family" then
		if type(assigned) ~= "string" then
			Names.argument(3, "string", assigned)
		end
		fields.Family = assigned
	elseif key == "Weight" then
		fields.Weight = checkItem(assigned, "FontWeight")
	elseif key == "Style" then
		fields.Style = checkItem(assigned, "FontStyle")
	elseif key == "Bold" then
		local weights = fontEnums[value].FontWeight
		fields.Weight = if assigned then weights.Bold else weights.Regular
	else
		Names.invalid(quoted(key), "Font")
	end
end

FontKind.meta.__eq = function(a: FontValue, b: FontValue): boolean
	return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style
end

FontKind.meta.__tostring = function(value: FontValue): string
	return ("Font { Family = %s, Weight = %s, Style = %s }"):format(value.Family, value.Weight.Name, value.Style.Name)
end

local function constructor(enums: Enums, catalog: FontCatalog?): FontConstructor
	local function make(family: string, weight: unknown?, style: unknown?): FontValue
		local made: FontValue = Names.make(FontKind, {
			Family = family,
			Weight = if weight == nil then enums.FontWeight.Regular else checkItem(weight, "FontWeight"),
			Style = if style == nil then enums.FontStyle.Normal else checkItem(style, "FontStyle"),
			[ENUMS] = enums,
		})
		fontEnums[made] = enums
		return made
	end

	return {
		new = function(family: string, weight: EnumItem?, style: EnumItem?): FontValue
			if type(family) ~= "string" then
				Names.argument(1, "string", family)
			end
			return make(family, weight, style)
		end,
		fromName = function(name: string, weight: EnumItem?, style: EnumItem?): FontValue
			return make("rbxasset://fonts/families/" .. name .. ".json", weight, style)
		end,
		fromId = function(id: number | string, weight: EnumItem?, style: EnumItem?): FontValue
			return make("rbxassetid://" .. tostring(id), weight, style)
		end,
		fromEnum = function(font: EnumItem): FontValue
			checkItem(font, "Font")
			local entry = if catalog ~= nil then catalog[font.Name] else nil
			if entry == nil then
				if catalog == nil then
					error("Font.fromEnum requires a reflection snapshot with fonts", 2)
				end
				return error(("%s can't be passed to Font.fromEnum"):format(tostring(font)), 2)
			end
			local found = entry
			return make(found.family, enums.FontWeight[found.weight], enums.FontStyle[found.style])
		end,
	}
end

return { constructor = constructor }
