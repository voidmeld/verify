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

return nil
