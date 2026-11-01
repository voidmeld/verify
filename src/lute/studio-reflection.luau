--!strict

local fs = require "@std/fs"
local Snapshot = require "../roblox/reflection-snapshot"
local Chunk = require "./chunk"
local Wire = require "./wire"

export type Execute = (code: string) -> string

export type Options = {
	classes: { string }?,
	enums: { string }?,
	services: boolean?,
	batchSize: number?,
	framework: string?,
}

export type Probe = { name: string, source: string, tolerance: number? }
export type ProbeResults = { engineVersion: string?, results: { [string]: string } }

type Fields = { [string]: unknown }

local DATATYPE_ENUMS = {
	"ContentSourceType",
	"EasingDirection",
	"EasingStyle",
	"Font",
	"FontStyle",
	"FontWeight",
	"KeyInterpolationMode",
	"RaycastFilterType",
}
local GLOBALS = "{ game = game, Instance = Instance, Enum = Enum, BrickColor = BrickColor, Font = Font, typeof = typeof,"
	.. " host = { read = function(value, key) return value[key] end,"
	.. " components = function(value) return { value:GetComponents() } end },"
	.. " version = version, security = SecurityCapabilities.fromCurrent():Add(Enum.SecurityCapability.Plugin),"
	.. " classSecurity = SecurityCapabilities.new(table.unpack(Enum.SecurityCapability:GetEnumItems())) }"

local function optionalString(value: unknown): string?
	if value == nil then
		return nil
	end
	assert(type(value) == "string")
	return value
end

local function checkedString(value: unknown): string
	assert(type(value) == "string")
	return value
end

local function literal(names: { string }): string
	local quoted: { string } = {}
	for _, name in names do
		table.insert(quoted, string.format("%q", name))
	end
	return "{" .. table.concat(quoted, ", ") .. "}"
end

local function program(framework: string): (part: string, names: { string }, services: boolean) -> string
	local encoding = fs.readFileToString(framework .. "/src/roblox/reflection-encoding.luau")
	local capture = fs.readFileToString(framework .. "/src/roblox/reflection-capture.luau")
	local prefix = "local Encoding = (function()\n"
		.. encoding
		.. "\nend)()\nlocal Capture = (function()\n"
		.. capture
		.. "\nend)()\nreturn Encoding.serialize(Capture.capture("
		.. GLOBALS
		.. ", Encoding.encode, "
	return function(part: string, names: { string }, services: boolean): string
		return prefix
			.. ("{ part = %q, names = %s, services = %s }))\n"):format(part, literal(names), tostring(services))
	end
end

local function record(text: string, part: string): Fields
	local parsed, value: unknown = pcall(Wire.parse, text)
	assert(parsed and type(value) == "table", "Studio returned an unreadable " .. part .. " capture")
	return Wire.record(value)
end

local function batches(names: { string }, size: number): { { string } }
	local out: { { string } } = {}
	for start = 1, #names, size do
		table.insert(out, table.move(names, start, math.min(start + size - 1, #names), 1, {}))
	end
	return out
end

local function keys(set: { [string]: boolean }): { string }
	local out: { string } = {}
	for name in set do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function export(execute: Execute, options: Options?): Snapshot.Snapshot
	local settings: Options = options or {}
	local size = settings.batchSize or 25
	assert(size >= 1 and size % 1 == 0, "batchSize must be a positive whole number")
	local services = settings.services == true
	local code = program(settings.framework or ".")
	local function run(part: string, names: { string }): Fields
		return record(execute(code(part, names, services)), part)
	end

	local index = run("index", {})
	local superclasses: { [string]: string | false } = {}
	for _, raw in Wire.array(index.classes) do
		local entry = Wire.record(raw)
		superclasses[checkedString(entry.name)] = false
	end
	for _, raw in Wire.array(index.classes) do
		local entry = Wire.record(raw)
		local super = optionalString(entry.superclass)
		if super ~= nil and superclasses[super] ~= nil then
			superclasses[checkedString(entry.name)] = super
		end
	end
	local known: { [string]: boolean } = {}
	for _, name in Wire.array(index.enums) do
		known[checkedString(name)] = true
	end

	local wanted: { [string]: boolean } = {}
	if settings.classes == nil then
		for name in superclasses do
			wanted[name] = true
		end
	else
		for _, name in settings.classes do
			local current: string? = name
			while current ~= nil and not wanted[current] do
				local super = superclasses[current]
				assert(super ~= nil, "Studio reflection has no class " .. current)
				wanted[current] = true
				current = if type(super) == "string" then super else nil
			end
		end
	end

	local classes: Fields = {}
	for _, batch in batches(keys(wanted), size) do
		for name, entry in run("classes", batch) do
			local fields = Wire.record(entry)
			local super = superclasses[name]
			fields.superclass = if type(super) == "string" then super else nil
			classes[name] = fields
		end
	end

	local families: { [string]: boolean } = {}
	if settings.classes == nil and settings.enums == nil then
		families = table.clone(known)
	else
		for _, name in DATATYPE_ENUMS do
			families[name] = known[name]
		end
		local requested: { string } = settings.enums or {}
		for _, name in requested do
			assert(known[name], "Studio has no enum " .. name)
			families[name] = true
		end
		for _, entry in classes do
			local fields = Wire.record(entry)
			for _, value in Wire.record(fields.properties) do
				local property = Wire.record(value)
				local family = string.match(checkedString(property.datatype), "^Enum%.(.+)$")
				if family ~= nil and known[family] then
					families[family] = true
				end
			end
			for _, value in Wire.record(fields.defaults) do
				if type(value) == "table" and Wire.record(value)["$"] == "EnumItem" then
					families[checkedString(Wire.record(value).family)] = true
				end
			end
		end
	end

	local enums: Fields = {}
	for _, batch in batches(keys(families), size * 2) do
		for name, items in run("enums", batch) do
			enums[name] = items
		end
	end

	local engine = run("engine", {})
	return Snapshot.decode {
		schemaVersion = Snapshot.SCHEMA_VERSION,
		engineVersion = index.engineVersion,
		classes = classes,
		enums = enums,
		brickColors = engine.brickColors,
		fonts = engine.fonts,
	}
end

local PREFIX = "^[^%s:]+:%d+: "

local function normalize(message: string): string
	return (string.gsub(message, PREFIX, "", 1))
end

local function outcome(ran: boolean, value: unknown): string
	if ran then
		return "ok: " .. tostring(value)
	end
	return "error: " .. normalize(tostring(value))
end

local function probeStudio(execute: Execute, probes: { Probe }): ProbeResults
	local pieces = { "local probes = {}" }
	for _, probe in probes do
		table.insert(pieces, ("table.insert(probes, { name = %q, run = function()"):format(probe.name))
		table.insert(pieces, probe.source)
		table.insert(pieces, "end })")
	end
	table.insert(pieces, ("local PREFIX = %q"):format(PREFIX))
	table.insert(
		pieces,
		[[
local results = {}
for _, probe in probes do
	local ran, value = pcall(probe.run)
	results[probe.name] = if ran
		then "ok: " .. tostring(value)
		else "error: " .. (string.gsub(tostring(value), PREFIX, "", 1))
end
return game:GetService("HttpService"):JSONEncode({ engineVersion = version(), results = results })]]
	)
	local reply = record(execute(table.concat(pieces, "\n")), "probe")
	local results: { [string]: string } = {}
	for name, value in Wire.record(reply.results) do
		results[name] = checkedString(value)
	end
	return { engineVersion = optionalString(reply.engineVersion), results = results }
end

local function probeLocal(environment: { [string]: unknown }, probes: { Probe }): { [string]: string }
	local results: { [string]: string } = {}
	for _, probe in probes do
		local ran, value = pcall(function(): unknown
			local result = Chunk.load(probe.source, { name = "probe", environment = environment })()
			return result
		end)
		results[probe.name] = outcome(ran, value)
	end
	return results
end

return {
	export = export,
	probeStudio = probeStudio,
	probeLocal = probeLocal,
}
