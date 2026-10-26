--!strict

local Datatypes = require "./datatypes"
local Names = require "./datatypes/names"
local Enum = require "./datatypes/enum"

export type Vector = { X: number, Y: number }
export type Dimension = { Scale: number, Offset: number }
export type Dimensions = { X: Dimension, Y: Dimension }
export type Font = { Family: string, Weight: unknown, Style: unknown }
export type TextParameters = { Text: string, Size: number, Font: Font, Width: number, RichText: boolean? }

local function number(value: unknown): number
	assert(type(value) == "number", "expected a number")
	return value
end

local function string(value: unknown): string
	assert(type(value) == "string", "expected a string")
	return value
end

local function fields(value: unknown, kind: string): Names.Fields
	assert(Datatypes.typeName(value) == kind, "expected " .. kind)
	return Names.fields(value)
end

local function vector(value: unknown): Vector
	local valueFields = fields(value, "Vector2")
	return { X = number(valueFields.X), Y = number(valueFields.Y) }
end

local function dimension(value: unknown): Dimension
	local valueFields = fields(value, "UDim")
	return { Scale = number(valueFields.Scale), Offset = number(valueFields.Offset) }
end

local function dimensions(value: unknown): Dimensions
	local valueFields = fields(value, "UDim2")
	return { X = dimension(valueFields.X), Y = dimension(valueFields.Y) }
end

local function font(value: unknown): Font
	local valueFields = fields(value, "Font")
	return { Family = string(valueFields.Family), Weight = valueFields.Weight, Style = valueFields.Style }
end

local function enumName(value: unknown, family: string): string
	assert(Enum.isItem(value) and Enum.enumType(value) == family, "expected Enum." .. family)
	return string(Names.fields(value).Name)
end

return {
	number = number,
	string = string,
	vector = vector,
	dimension = dimension,
	dimensions = dimensions,
	font = font,
	enumName = enumName,
}
