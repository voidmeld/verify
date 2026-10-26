--!strict

local Test = require "./harness"
local describe, it, expect = Test.describe, Test.it, Test.expect

local Lute = require "../src/lute"
local Roblox = require "../src/roblox"

describe("reflection reuse across engines", function()
	it("builds one engine's class overlay without changing another engine from the same snapshot", function()
		local snapshot = Lute.fixture.load()
		local properties: { [string]: unknown } = { Probe = 7 }
		local options: Roblox.ReflectionSnapshotOptions = { classes = { Frame = { properties = properties } } }
		local probed = Roblox.reflectionSnapshot.bridge(snapshot, options)
		local plain = Roblox.reflectionSnapshot.bridge(snapshot)
		local withProbe = probed.environment.createInstance "Frame"
		expect(withProbe.Probe):toBe(7)
		local without = plain.environment.createInstance "Frame"
		expect(function()
			local _ = without.Probe
		end):toThrow()
		local again = Roblox.reflectionSnapshot.bridge(snapshot).environment.createInstance "Frame"
		expect(again.BackgroundTransparency):toBe(without.BackgroundTransparency)
	end)
end)

describe("chunk reuse across environments", function()
	it("runs the same source with separate state in each environment", function()
		local source = "count = (count or 0) + 1\nreturn count"
		local first: { [string]: unknown } = {}
		local second: { [string]: unknown } = {}
		local load = Lute.chunk.load
		expect(load(source, { environment = first, injectGlobals = false })()):toBe(1)
		expect(load(source, { environment = first, injectGlobals = false })()):toBe(2)
		expect(load(source, { environment = second, injectGlobals = false })()):toBe(1)
	end)
end)

return nil
