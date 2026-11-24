--!strict

local Names = require "./names"

export type EnumItem = {
	Name: string,
	Value: number,
	EnumType: EnumFamily,
	IsA: (self: EnumItem, family: string) -> boolean,
}
export type EnumFamily = {
	GetEnumItems: (self: EnumFamily) -> { EnumItem },
	FromName: (self: EnumFamily, name: string) -> EnumItem?,
	FromValue: (self: EnumFamily, value: number) -> EnumItem?,
	[string]: EnumItem,
}
export type Enums = {
	GetEnums: (self: Enums) -> { EnumFamily },
	[string]: EnumFamily,
}
export type ItemEntry = { name: string, value: number }
export type Catalog = { [string]: { ItemEntry } }

type Fields = Names.Fields

local NAME = {}
local ITEMS = {}
local SELF = {}

local ItemKind = Names.behavior "EnumItem"
local FamilyKind = Names.behavior "Enum"
local LazyFamilyKind = Names.behavior "Enum"
local EnumsKind = Names.behavior "Enums"
local LazyEnumsKind = Names.behavior "Enums"

local familyNames: { [unknown]: string } = {}
local familyItems: { [unknown]: { EnumItem } } = {}
local enumFamilies: { [unknown]: { EnumFamily } } = {}
local itemValues: { [unknown]: EnumItem } = {}
Names.weak(familyNames)
Names.weak(familyItems)
Names.weak(enumFamilies)
Names.weak(itemValues)

local function familyName(family: unknown): string
	return familyNames[family]
end

local function itemFamily(item: unknown): string
	return familyName(Names.fields(item).EnumType)
end

local function label(item: Fields): string
	return ('"Enum.%s.%s"'):format(familyName(item.EnumType), tostring(item.Name))
end

local function items(family: unknown): { EnumItem }
	return familyItems[family]
end

local function isA(self: EnumItem, family: string): boolean
	return itemFamily(self) == family
end

ItemKind.fields.__index = function(item: Fields, key: unknown): unknown
	if key == "IsA" then
		return isA
	end
	return Names.invalid(key, label(item))
end
ItemKind.meta.__newindex = function(_: unknown, key: unknown, _value: unknown)
	Names.invalid(key, "EnumItem")
end
EnumsKind.meta.__newindex = function(_: unknown, key: unknown, _value: unknown)
	Names.invalid(key, "Enums")
end
ItemKind.meta.__eq = function(a: EnumItem, b: EnumItem): boolean
	return a.Name == b.Name and itemFamily(a) == itemFamily(b)
end
ItemKind.meta.__tostring = function(item: EnumItem): string
	return ("Enum.%s.%s"):format(itemFamily(item), item.Name)
end

local familyMethods: { [unknown]: unknown } = {
	GetEnumItems = function(self: EnumFamily): { EnumItem }
		return table.clone(items(self))
	end,
	FromName = function(self: EnumFamily, name: string): EnumItem?
		for _, item in items(self) do
			if item.Name == name then
				return item
			end
		end
		return nil
	end,
	FromValue = function(self: EnumFamily, value: number): EnumItem?
		for _, item in items(self) do
			if item.Value == value then
				return item
			end
		end
		return nil
	end,
}

local function familyLabel(family: Fields): string
	return ('"Enum.%s"'):format(familyNames[family])
end

FamilyKind.fields.__index = function(family: Fields, key: unknown): unknown
	local method = familyMethods[key]
	if method ~= nil then
		return method
	end
	return Names.invalid(key, familyLabel(family))
end
FamilyKind.meta.__newindex = function(_: unknown, key: unknown, _value: unknown)
	Names.invalid(key, "Enum")
end
FamilyKind.meta.__tostring = familyName

local function getEnums(self: Enums): { EnumFamily }
	return table.clone(enumFamilies[self])
end

EnumsKind.fields.__index = function(_: Fields, key: unknown): unknown
	if key == "GetEnums" then
		return getEnums
	end
	return Names.invalid(key, '"Enum"')
end
EnumsKind.meta.__tostring = function(): string
	return "Enums"
end

local function item(family: unknown, name: string, value: number?): EnumItem
	local made: EnumItem = Names.make(ItemKind, { Name = name, Value = value, EnumType = family })
	itemValues[made] = made
	return made
end

local function catalog(source: Catalog): Enums
	local root: Fields = {}
	local families: { EnumFamily } = {}
	local names: { string } = {}
	for name in source do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local fields: Fields = { [NAME] = name }
		local family: EnumFamily = Names.make(FamilyKind, fields)
		familyNames[family], familyNames[fields] = name, name
		local list: { EnumItem } = {}
		for _, entry in source[name] do
			local created = item(family, entry.name, entry.value)
			table.insert(list, created)
			fields[entry.name] = created
		end
		fields[ITEMS] = table.freeze(list)
		familyItems[family] = list
		root[name] = family
		table.insert(families, family)
	end
	root[ITEMS] = table.freeze(families)
	local made: Enums = Names.make(EnumsKind, root)
	enumFamilies[made] = families
	return made
end

LazyFamilyKind.fields.__index = function(fields: Fields, key: unknown): unknown
	if type(key) ~= "string" then
		return nil
	end
	local created = item(fields[SELF], key, nil)
	rawset(fields, key, created)
	return created
end
LazyFamilyKind.meta.__tostring = familyName

LazyEnumsKind.fields.__index = function(root: Fields, key: unknown): unknown
	if type(key) ~= "string" then
		return nil
	end
	local fields: Fields = { [NAME] = key }
	local family: EnumFamily = Names.make(LazyFamilyKind, fields)
	familyNames[family], familyNames[fields] = key, key
	fields[SELF] = family
	rawset(root, key, family)
	return family
end
LazyEnumsKind.meta.__tostring = function(): string
	return "Enums"
end

local function lazy(): Enums
	return Names.make(LazyEnumsKind, {})
end

local function enumType(value: unknown): string
	return itemFamily(value)
end

local function isItem(value: unknown): boolean
	return Names.is(value, ItemKind)
end

return {
	catalog = catalog,
	lazy = lazy,
	enumType = enumType,
	isItem = isItem,
	itemValue = function(value: unknown): EnumItem
		return itemValues[value]
	end,
}
