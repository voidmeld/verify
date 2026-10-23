--!strict

local fs = require "@std/fs"
local Path = require "@std/path"
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
	load = load,
	bridge = bridge,
	save = save,
	exportStudio = StudioReflection.export,
	probeStudio = StudioReflection.probeStudio,
	probeLocal = StudioReflection.probeLocal,
	serialize = Encoding.serialize,
}
