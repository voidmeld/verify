--!strict

local fs = require "@std/fs"
local Path = require "@std/path"
local luau = require "@lute/luau"
local PlaceBoot = require "../roblox/place-boot"
local Encoding = require "../roblox/reflection-encoding"
local FixtureBridge = require "../roblox/fixture-bridge"
local Snapshot = require "../roblox/reflection-snapshot"
local StudioReflection = require "./studio-reflection"
local Wire = require "./wire"

export type Options = Snapshot.Options
export type Snapshot = Snapshot.Snapshot
export type ExportOptions = StudioReflection.Options
export type Execute = StudioReflection.Execute
export type Probe = StudioReflection.Probe
export type ProbeResults = StudioReflection.ProbeResults
export type PlaceHost = PlaceBoot.Host<luau.Bytecode, () -> unknown>

local host: PlaceHost = {
	readFile = fs.readFileToString,
	compile = luau.compile,
	load = function(bytecode: luau.Bytecode, chunkName: string, environment: { [string]: unknown }): () -> unknown
		return luau.load(bytecode, chunkName, environment)
	end,
	encodeJson = Wire.encode,
	decodeJson = Wire.parse,
}

local files: PlaceBoot.Files = {
	exists = fs.exists,
	fileType = fs.type,
	listDirectory = function(path: string): { { name: string, type: string } }
		local entries: { { name: string, type: string } } = {}
		for _, entry in fs.listDirectory(path) do
			local kind: string = entry.type
			table.insert(entries, { name = entry.name, type = kind })
		end
		return entries
	end,
}

local DEFAULT_PATH =
	Path.format(Path.join(Path.dirname(Path.resolve(debug.info(1, "s"))), "fixtures/roblox-0.744.0.7441077.json"))

local function load(source: string?): Snapshot.Snapshot
	local path = source or DEFAULT_PATH
	local decoded = Wire.parse(fs.readFileToString(path))
	assert(type(decoded) == "table", "reflection snapshot is not a JSON object: " .. path)
	return decoded :: Snapshot.Snapshot
end

local function bridge(snapshot: (string | Snapshot.Snapshot)?, options: Options?): FixtureBridge.Bridge
	return Snapshot.bridge(if type(snapshot) == "table" then snapshot else load(snapshot), options)
end

local function save(path: string, snapshot: unknown)
	fs.writeStringToFile(path, Encoding.serialize(snapshot) .. "\n")
end

return {
	host = table.freeze(host),
	files = table.freeze(files),
	load = load,
	bridge = bridge,
	save = save,
	exportStudio = StudioReflection.export,
	probeStudio = StudioReflection.probeStudio,
	probeLocal = StudioReflection.probeLocal,
	serialize = Encoding.serialize,
}
