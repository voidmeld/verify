--!strict

local fs = require "@std/fs"
local FixtureBridge = require "../roblox/fixture-bridge"
local Snapshot = require "../roblox/reflection-snapshot"
local Wire = require "./wire"

export type Options = Snapshot.Options

local function load(path: string): Snapshot.Snapshot
	local decoded = Wire.parse(fs.readFileToString(path))
	assert(type(decoded) == "table", "reflection snapshot is not a JSON object: " .. path)
	return decoded :: Snapshot.Snapshot
end

local function bridge(snapshot: string | Snapshot.Snapshot, options: Options?): FixtureBridge.Bridge
	return Snapshot.bridge(if type(snapshot) == "string" then load(snapshot) else snapshot, options)
end

return { load = load, bridge = bridge }
