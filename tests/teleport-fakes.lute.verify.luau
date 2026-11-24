--!strict

local Test = require "./harness"
local Lute = require "../src/lute"
local Roblox = require "../src/roblox"
local expect, it = Test.expect, Test.it

it("teleport options copy data per instance and preserve clone state", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local first, second = engine.newInstance "TeleportOptions", engine.newInstance "TeleportOptions"
	local set, get = env.method(first, "SetTeleportData"), env.method(first, "GetTeleportData")
	expect(get(first)):toBe(nil)
	local data = { nested = { value = 1 }, position = engine.datatypes.Vector3.one }
	set(first, data)
	data.nested.value = 2
	local returned = get(first)
	assert(type(returned) == "table")
	table.clear(returned)
	expect(get(first)):toEqual { nested = { value = 1 }, position = engine.datatypes.Vector3.one }
	expect(env.method(second, "GetTeleportData")(second)):toBe(nil)
	local clone = assert(first:Clone())
	set(first, false)
	expect(get(first)):toBe(false)
	expect(env.method(clone, "GetTeleportData")(clone)):toEqual {
		nested = { value = 1 },
		position = engine.datatypes.Vector3.one,
	}
	expect(pcall(set, first, { invalid = engine.newInstance "Part" })):toBe(false)
	expect(get(first)):toBe(false)
	set(first, nil)
	expect(get(first)):toBe(nil)
end)

it("arrival fixtures isolate server join data and local client teleport data", function()
	local engine = Lute.fixture.bridge().placeEngine()
	local env = engine.environment
	local first, second = engine.newInstance("Player", true), engine.newInstance("Player", true)
	local service = engine.service "TeleportService"
	local join = env.method(first, "GetJoinData")
	local localData = env.method(service, "GetLocalPlayerTeleportData")
	expect(join(first)):toEqual {}
	expect(localData(service)):toBe(nil)
	local data = { TeleportData = { value = 1 }, LaunchData = "fixture" }
	Roblox.teleportFakes.setJoinData(env, first, data)
	data.TeleportData.value = 2
	Roblox.teleportFakes.setLocalPlayerTeleportData(env, service, false)
	expect(join(first)):toEqual { TeleportData = { value = 1 }, LaunchData = "fixture" }
	expect(env.method(second, "GetJoinData")(second)):toEqual {}
	expect(localData(service)):toBe(false)
	local result = join(first)
	assert(type(result) == "table")
	table.clear(result)
	expect(join(first)):toEqual { TeleportData = { value = 1 }, LaunchData = "fixture" }
	expect(pcall(Roblox.teleportFakes.setJoinData, env, service, {})):toBe(false)
	first:Destroy()
	expect(pcall(Roblox.teleportFakes.setJoinData, env, first, {})):toBe(false)
	local cycle: { [string]: unknown } = {}
	cycle.self = cycle
	expect(pcall(Roblox.teleportFakes.setLocalPlayerTeleportData, env, service, cycle)):toBe(false)
	expect(localData(service)):toBe(false)
end)

return nil
