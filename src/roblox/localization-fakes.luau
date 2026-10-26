--!strict

local Environment = require "./environment-types"

export type Entry = { Key: string?, Source: string?, Context: string?, Values: { [string]: string }? }
export type Translator = {
	LocaleId: string,
	FormatByKey: (Translator, key: string, arguments: { [string | number]: unknown }?) -> string,
	Translate: (Translator, context: unknown, text: string) -> string,
}

local function copyEntry(entry: Entry): Entry
	local values = entry.Values
	return {
		Key = entry.Key,
		Source = entry.Source,
		Context = entry.Context,
		Values = if values then table.clone(values) else {},
	}
end

local function format(text: string, arguments: { [string | number]: unknown }?): string
	if arguments == nil then
		return text
	end
	local supplied = arguments
	return (
		string.gsub(text, "{([%w_]+)}", function(name: string): string
			local index = tonumber(name)
			local value = if index ~= nil then supplied[index] else supplied[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

local function attach(environment: Environment.Environment)
	local tables: { [Environment.Instance]: { Entry } } = {}
	setmetatable(tables, { __mode = "k" })
	local empty: { Entry } = {}
	local function entriesOf(object: Environment.Instance): { Entry }
		local stored = tables[object]
		return if stored ~= nil then stored else empty
	end
	environment.fake("LocalizationTable.SetEntries", function(object: Environment.Instance, entries: { Entry })
		assert(type(entries) == "table", "SetEntries expects a table of entries")
		local stored: { Entry } = {}
		for _, entry in entries do
			table.insert(stored, copyEntry(entry))
		end
		tables[object] = stored
	end)
	environment.fake("LocalizationTable.GetEntries", function(object: Environment.Instance): { Entry }
		local result: { Entry } = {}
		for _, entry in entriesOf(object) do
			table.insert(result, copyEntry(entry))
		end
		return result
	end)
	environment.fake(
		"LocalizationTable.GetTranslator",
		function(object: Environment.Instance, locale: string): Translator
			local function translated(entry: Entry): string
				local values = entry.Values
				local localized = if values then values[locale] else nil
				return localized or entry.Source or ""
			end
			local translator: Translator = {
				LocaleId = locale,
				FormatByKey = function(
					_self: Translator,
					key: string,
					arguments: { [string | number]: unknown }?
				): string
					for _, entry in entriesOf(object) do
						if entry.Key == key then
							return format(translated(entry), arguments)
						end
					end
					error(`LocalizationTable has no entry for key {key}`, 2)
				end,
				Translate = function(_self: Translator, _context: unknown, text: string): string
					for _, entry in entriesOf(object) do
						if entry.Source == text then
							return translated(entry)
						end
					end
					return text
				end,
			}
			return translator
		end
	)
end

return { attach = attach }
